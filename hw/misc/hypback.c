/*
 * QEMU Win9x Hypercall Backdoor PCI Device
 *
 * Provides a 64K MMIO BAR through which a Win9x guest VxD can issue
 * hypercalls to the QEMU host.  The guest populates arguments in BAR0
 * and writes the doorbell (offset 0x0004) to trigger dispatch.
 *
 * PCI identity: vendor 0x1234 (QEMU), device 0xbeef
 *
 * Pattern reference: hw/misc/edu.c (single BAR MMIO doorbell)
 *
 * Copyright (c) 2024 Win9x-QEMU98 Project
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "qemu/osdep.h"
#include "qemu/log.h"
#include "qemu/units.h"
#include "qemu/bitops.h"
#include "hw/pci/pci.h"
#include "hw/pci/pci_device.h"
#include "hw/pci/msi.h"
#include "hw/misc/hypback.h"
#include "qom/object.h"
#include "qemu/module.h"
#include "qapi/qapi-commands-misc.h"
#include "qapi/error.h"

#define TYPE_PCI_HYPBACK_DEVICE "hypback"
typedef struct HypbackState HypbackState;
DECLARE_INSTANCE_CHECKER(HypbackState, HYPBACK, TYPE_PCI_HYPBACK_DEVICE)

/* ------------------------------------------------------------------ */
/*  Handler Registry (global)                                         */
/* ------------------------------------------------------------------ */

#define HYP_MAX_HANDLERS 8

typedef struct HypbackHandlerEntry {
    uint32_t op_start;
    uint32_t op_end;
    HypbackHandler handler;
    void* opaque;
} HypbackHandlerEntry;

static HypbackHandlerEntry hypback_handlers[HYP_MAX_HANDLERS];
static unsigned hypback_handler_count;

/* Global pointer to the first hypback device, for the QMP test handler */
static HypbackState* hypback_device;

/* ------------------------------------------------------------------ */
/*  Device State                                                      */
/* ------------------------------------------------------------------ */

struct HypbackState {
    PCIDevice pdev;
    MemoryRegion mmio;

    /* Doorbell header (written by guest) */
    uint32_t dw0; /* op | len                         */
    uint32_t dw1; /* arg_count | flags | abi_version  */

    /* Argument region (32 × 8 bytes = 256 bytes) */
    uint64_t args[HYP_ARG_COUNT];

    /* Signal masks */
    uint32_t guest_signal; /* guest→host (RW by guest, RO by host) */
    uint32_t host_signal; /* host→guest (RO by guest, RW by host) */

    /* Completion fence — monotonic 64-bit counter */
    uint64_t fence;

    /* MSI interrupt support (optional, fallback to poll if unavailable) */
    bool msi_enabled;
};

/* ------------------------------------------------------------------ */
/*  Handler Registry Functions                                        */
/* ------------------------------------------------------------------ */

bool hypback_register_handler(const uint32_t op_start, const uint32_t op_end, const HypbackHandler handler, void* opaque) {
    assert(handler);
    assert(op_start <= op_end);

    /* Check for overlapping ranges */
    for (unsigned i = 0; i < hypback_handler_count; i++) {
        if (op_start <= hypback_handlers[i].op_end && op_end >= hypback_handlers[i].op_start) {
            return false;
        }
    }

    if (hypback_handler_count >= HYP_MAX_HANDLERS) {
        return false;
    }

    hypback_handlers[hypback_handler_count] = (HypbackHandlerEntry){.op_start = op_start, .op_end = op_end, .handler = handler, .opaque = opaque,};
    hypback_handler_count++;
    return true;
}

void hypback_unregister_handler(const uint32_t op_start, const uint32_t op_end) {
    for (unsigned i = 0; i < hypback_handler_count; i++) {
        if (hypback_handlers[i].op_start == op_start && hypback_handlers[i].op_end == op_end) {
            /* Compact the array by shifting remaining entries */
            memmove(&hypback_handlers[i], &hypback_handlers[i + 1], (hypback_handler_count - i - 1) * sizeof(HypbackHandlerEntry));
            hypback_handler_count--;
            return;
        }
    }
}

/* ------------------------------------------------------------------ */
/*  Built-in Test Handler (registered via QMP)                        */
/* ------------------------------------------------------------------ */

static void hypback_test_handler(void* opaque, uint32_t op, uint32_t arg_count, const uint64_t* args, uint64_t* fence) {
    HypbackState* s = opaque;

    /* Store call metadata in observable registers */
    s->guest_signal = op;
    s->host_signal = arg_count;
    qatomic_inc_fetch(fence);
}

/* ------------------------------------------------------------------ */
/*  QMP Commands                                                      */
/* ------------------------------------------------------------------ */

void qmp_x_hypback_register_handler(const int64_t op_start, const int64_t op_end, Error** errp) {
    if (op_start < 0 || op_start > 0xFFFF || op_end < 0 || op_end > 0xFFFF || op_start > op_end) {
        error_setg(errp, "Invalid op range: [0x%04"PRIx64", 0x%04"PRIx64"]", op_start, op_end);
        return;
    }

    if (!hypback_device) {
        error_setg(errp, "No hypback device present");
        return;
    }

    if (!hypback_register_handler((uint32_t)op_start, (uint32_t)op_end, hypback_test_handler, hypback_device)) {
        error_setg(
            errp,
            "Failed to register handler for op range " "[0x%04"PRIx64", 0x%04"PRIx64"]: " "range overlaps or handler table full",
            op_start,
            op_end
        );
    }
}

void qmp_x_hypback_unregister_handler(const int64_t op_start, const int64_t op_end, Error** errp) {
    if (op_start < 0 || op_start > 0xFFFF || op_end < 0 || op_end > 0xFFFF || op_start > op_end) {
        error_setg(errp, "Invalid op range: [0x%04"PRIx64", 0x%04"PRIx64"]", op_start, op_end);
        return;
    }

    hypback_unregister_handler((uint32_t)op_start, (uint32_t)op_end);
}

/* ------------------------------------------------------------------ */
/*  Doorbell Dispatch                                                 */
/* ------------------------------------------------------------------ */

static void hypback_dispatch(HypbackState* s) {
    const uint32_t op = s->dw0 & HYP_DW0_OP_MASK;
    const uint32_t arg_count = (s->dw1 & HYP_DW1_ARG_COUNT_MASK) >> HYP_DW1_ARG_COUNT_SHIFT;

    if (arg_count > HYP_ARG_COUNT) {
        qemu_log_mask(LOG_GUEST_ERROR, "hypback: arg_count %u exceeds maximum %u\n", arg_count, HYP_ARG_COUNT);
        return;
    }

    for (unsigned i = 0; i < hypback_handler_count; i++) {
        if (op >= hypback_handlers[i].op_start && op <= hypback_handlers[i].op_end) {
            hypback_handlers[i].handler(hypback_handlers[i].opaque, op, arg_count, s->args, &s->fence);

            /* Fire MSI interrupt after handler completes, if enabled.
             * This lets the guest VxD use IRQ-based completion instead
             * of polling the fence register. */
            if (s->msi_enabled) {
                msi_notify(&s->pdev, 0);
            }
            return;
        }
    }

    qemu_log_mask(LOG_GUEST_ERROR, "hypback: no handler registered for op 0x%04x\n", op);
}

/* ------------------------------------------------------------------ */
/*  MMIO Read / Write                                                 */
/* ------------------------------------------------------------------ */

static uint64_t hypback_mmio_read(void* opaque, const hwaddr addr, const unsigned size) {
    const HypbackState* s = opaque;
    uint64_t val = ~0ULL;

    switch (addr) {
        case HYP_DOORBELL_DW0:
            val = s->dw0;
            break;
        case HYP_DOORBELL_DW1:
            val = s->dw1;
            break;
        case HYP_HOST_SIGNAL:
            val = s->host_signal;
            break;
        case HYP_FENCE_LO:
            if (size == 8) {
                val = qatomic_read(&s->fence);
            }
            else {
                val = (uint32_t)qatomic_read(&s->fence);
            }
            break;
        case HYP_FENCE_HI:
            val = (uint32_t)(qatomic_read(&s->fence) >> 32);
            break;
        default:
            /* Argument region: offset 0x0008 .. 0x0107 */
            if (addr >= HYP_ARG_BASE && addr < HYP_ARG_BASE + HYP_ARG_COUNT * sizeof(uint64_t)) {
                const unsigned idx = (addr - HYP_ARG_BASE) / sizeof(uint64_t);
                const unsigned byte_off = (addr - HYP_ARG_BASE) % sizeof(uint64_t);
                if (idx < HYP_ARG_COUNT) {
                    if (size == 8 && byte_off == 0) {
                        val = s->args[idx];
                    }
                    else {
                        /* Sub-8-byte or unaligned: extract the right bytes */
                        const uint64_t arg = s->args[idx];
                        val = arg >> (byte_off * 8) & MAKE_64BIT_MASK(0, size * 8);
                    }
                }
            }
            /* guest_signal: offset 0x0108 */
            else if (addr == HYP_GUEST_SIGNAL) {
                val = s->guest_signal;
            }
            /* Log ring: uninitialized region returns ~0 */
            break;
    }

    return val;
}

static void hypback_mmio_write(void* opaque, const hwaddr addr, const uint64_t val, unsigned size) {
    HypbackState* s = opaque;

    switch (addr) {
        case HYP_DOORBELL_DW0:
            s->dw0 = (uint32_t)val;
            break;

        case HYP_DOORBELL_DW1:
            s->dw1 = (uint32_t)val;
            /* Writing DW1 rings the doorbell — dispatch the hypercall */
            hypback_dispatch(s);
            break;

        case HYP_GUEST_SIGNAL:
            s->guest_signal = (uint32_t)val;
            break;

        case HYP_HOST_SIGNAL:
            /* host_signal is read-only from guest perspective — ignore writes */
            qemu_log_mask(LOG_GUEST_ERROR, "hypback: guest attempted write to RO host_signal\n");
            break;

        default:
            /* Argument region */
            if (addr >= HYP_ARG_BASE && addr < HYP_ARG_BASE + HYP_ARG_COUNT * sizeof(uint64_t)) {
                const unsigned idx = (addr - HYP_ARG_BASE) / sizeof(uint64_t);
                const unsigned byte_off = (addr - HYP_ARG_BASE) % sizeof(uint64_t);
                if (idx < HYP_ARG_COUNT) {
                    if (size == 8 && byte_off == 0) {
                        s->args[idx] = val;
                    }
                    else {
                        /* Sub-8-byte write: only update the targeted bytes */
                        uint64_t mask = MAKE_64BIT_MASK(byte_off * 8, size * 8);
                        s->args[idx] = (s->args[idx] & ~mask) | ((val << (byte_off * 8)) & mask);
                    }
                }
            }
            /* Fence is read-only from guest perspective — ignore writes */
            else if (addr == HYP_FENCE_LO || addr == HYP_FENCE_HI) {
                qemu_log_mask(LOG_GUEST_ERROR, "hypback: guest attempted write to RO fence\n");
            }
            break;
    }
}

static const MemoryRegionOps hypback_mmio_ops = {
    .read = hypback_mmio_read,
    .write = hypback_mmio_write,
    .endianness = DEVICE_NATIVE_ENDIAN,
    .valid = {.min_access_size = 4, .max_access_size = 8,},
    .impl = {.min_access_size = 4, .max_access_size = 8,},
};

/* ------------------------------------------------------------------ */
/*  PCI Device Lifecycle                                              */
/* ------------------------------------------------------------------ */

static void pci_hypback_realize(PCIDevice* pdev, Error** errp) {
    HypbackState* s = HYPBACK(pdev);
    uint8_t* pci_conf = pdev->config;

    /* Store global reference for QMP test handler */
    if (!hypback_device) {
        hypback_device = s;
    }

    /* Set interrupt pin for INTx fallback when MSI is unavailable */
    pci_config_set_interrupt_pin(pci_conf, 1);

    /* Try to enable MSI. If it fails (e.g. on older machine types),
     * we fall back to poll-only completion — the VxD will detect
     * this and use fence polling instead. */
    if (msi_init(pdev, 0, 1, true, false, NULL) == 0) {
        s->msi_enabled = true;
    }
    else {
        s->msi_enabled = false;
    }

    memory_region_init_io(&s->mmio, OBJECT(s), &hypback_mmio_ops, s, "hypback-mmio", HYP_MMIO_SIZE);
    pci_register_bar(pdev, 0, PCI_BASE_ADDRESS_SPACE_MEMORY, &s->mmio);
}

static void pci_hypback_exit(PCIDevice* pdev) {
    if (hypback_device == HYPBACK(pdev)) {
        hypback_device = NULL;
    }

    msi_uninit(pdev);
}

static void hypback_class_init(ObjectClass* class, const void* data) {
    DeviceClass* dc = DEVICE_CLASS(class);
    PCIDeviceClass* k = PCI_DEVICE_CLASS(class);

    k->realize = pci_hypback_realize;
    k->exit = pci_hypback_exit;
    k->vendor_id = PCI_VENDOR_ID_QEMU;
    k->device_id = 0xbeef;
    k->revision = 1;
    k->class_id = PCI_CLASS_OTHERS;
    set_bit(DEVICE_CATEGORY_MISC, dc->categories);
}

static const TypeInfo hypback_types[] = {
    {
        .name = TYPE_PCI_HYPBACK_DEVICE,
        .parent = TYPE_PCI_DEVICE,
        .instance_size = sizeof(HypbackState),
        .class_init = hypback_class_init,
        .interfaces = (const InterfaceInfo[]){{INTERFACE_CONVENTIONAL_PCI_DEVICE}, {},},
    }
};

DEFINE_TYPES(hypback_types)
