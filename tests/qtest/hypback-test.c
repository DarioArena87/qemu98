/*
 * QTest testcase for Win9x HypBack PCI device
 *
 * Tests the MMIO BAR0 read/write behavior: doorbell registers,
 * argument region (including sub-8-byte access), signal masks,
 * and the completion fence counter.  These tests serve as
 * documentation of the BAR0 layout for future VxD developers.
 *
 * Copyright (c) 2024 Win9x-QEMU98 Project
 *
 * This work is licensed under the terms of the GNU GPL, version 2 or later.
 * See the COPYING file in the top-level directory.
 */

#include "qemu/osdep.h"
#include "libqtest.h"
#include "libqos/pci.h"
#include "libqos/pci-pc.h"
#include "hw/pci/pci_regs.h"
#include "hw/misc/hypback.h"
#include "qobject/qdict.h"

static void test_hypback_pci_identity(void) {
    QTestState* qts = qtest_init("-device hypback,addr=04.0");
    QPCIBus* pcibus = qpci_new_pc(qts, NULL);
    QPCIDevice* dev = qpci_device_find(pcibus, QPCI_DEVFN(0x4, 0x0));
    g_assert_nonnull(dev);
    qpci_device_enable(dev);

    uint16_t vendor = qpci_config_readw(dev, PCI_VENDOR_ID);
    uint16_t device = qpci_config_readw(dev, PCI_DEVICE_ID);

    g_assert_cmphex(vendor, ==, 0x1234); /* PCI_VENDOR_ID_QEMU */
    g_assert_cmphex(device, ==, 0xBEEF);

    g_free(dev);
    qpci_free_pc(pcibus);
    qtest_quit(qts);
}

static void test_hypback_doorbell(void) {
    uint32_t val32;
    uint64_t val64;

    QTestState* qts = qtest_init("-device hypback,addr=04.0");
    QPCIBus* pcibus = qpci_new_pc(qts, NULL);
    QPCIDevice* dev = qpci_device_find(pcibus, QPCI_DEVFN(0x4, 0x0));
    g_assert_nonnull(dev);
    qpci_device_enable(dev);
    QPCIBar bar = qpci_iomap(dev, 0, NULL);

    /* DW0 and DW1 should start at 0 */
    qpci_memread(dev, bar, HYP_DOORBELL_DW0, &val32, sizeof(val32));
    g_assert_cmphex(val32, ==, 0x00000000);

    qpci_memread(dev, bar, HYP_DOORBELL_DW1, &val32, sizeof(val32));
    g_assert_cmphex(val32, ==, 0x00000000);

    /* Write DW0: op=0x1001, len=256 (0x0100) → DW0 = 0x01001001 */
    val32 = 0x01001001;
    qpci_memwrite(dev, bar, HYP_DOORBELL_DW0, &val32, sizeof(val32));
    qpci_memread(dev, bar, HYP_DOORBELL_DW0, &val32, sizeof(val32));
    g_assert_cmphex(val32, ==, 0x01001001);

    /* Write two arguments, then ring the doorbell.
     * No handler is registered for op 0x1001, so dispatch logs
     * a guest error but must not crash. */
    val64 = 0x0000000100000002ULL;
    qpci_memwrite(dev, bar, HYP_ARG_BASE, &val64, sizeof(val64));
    val32 = 0x00020001; /* arg_count=2, flags=0, abi=1 */
    qpci_memwrite(dev, bar, HYP_DOORBELL_DW1, &val32, sizeof(val32));
    qpci_memread(dev, bar, HYP_DOORBELL_DW1, &val32, sizeof(val32));
    g_assert_cmphex(val32, ==, 0x00020001);

    g_free(dev);
    qpci_free_pc(pcibus);
    qtest_quit(qts);
}

static void test_hypback_arguments(void) {
    uint64_t val64;
    uint32_t val32;

    QTestState* qts = qtest_init("-device hypback,addr=04.0");
    QPCIBus* pcibus = qpci_new_pc(qts, NULL);
    QPCIDevice* dev = qpci_device_find(pcibus, QPCI_DEVFN(0x4, 0x0));
    g_assert_nonnull(dev);
    qpci_device_enable(dev);
    QPCIBar bar = qpci_iomap(dev, 0, NULL);

    /* Verify arguments start at 0 */
    val64 = ~0ULL;
    qpci_memread(dev, bar, HYP_ARG_BASE, &val64, sizeof(val64));
    g_assert_cmphex(val64, ==, 0x0000000000000000ULL);

    /* Write a full 8-byte value to arg[0] */
    val64 = 0xDEADBEEFCAFEBABEULL;
    qpci_memwrite(dev, bar, HYP_ARG_BASE, &val64, sizeof(val64));
    qpci_memread(dev, bar, HYP_ARG_BASE, &val64, sizeof(val64));
    g_assert_cmphex(val64, ==, 0xDEADBEEFCAFEBABEULL);

    /* Test sub-8-byte write: write lo 32 bits of arg[0], verify hi preserved */
    val64 = 0xAAAAAAAA55555555ULL;
    qpci_memwrite(dev, bar, HYP_ARG_BASE, &val64, sizeof(val64));
    val32 = 0xBBBBBBBB;
    qpci_memwrite(dev, bar, HYP_ARG_BASE, &val32, sizeof(val32));
    qpci_memread(dev, bar, HYP_ARG_BASE, &val64, sizeof(val64));
    g_assert_cmphex(val64, ==, 0xAAAAAAAABBBBBBBBULL);

    /* Test sub-8-byte write: write hi 32 bits of arg[0] at offset 0x000C */
    val32 = 0xCCCCCCCC;
    qpci_memwrite(dev, bar, HYP_ARG_BASE + 4, &val32, sizeof(val32));
    qpci_memread(dev, bar, HYP_ARG_BASE, &val64, sizeof(val64));
    g_assert_cmphex(val64, ==, 0xCCCCCCCCBBBBBBBBULL);

    /* Test sub-8-byte read: read hi 32 bits at offset 0x000C */
    qpci_memread(dev, bar, HYP_ARG_BASE + 4, &val32, sizeof(val32));
    g_assert_cmphex(val32, ==, 0xCCCCCCCC);

    /* Write all 32 argument slots */
    for (int i = 0; i < HYP_ARG_COUNT; i++) {
        val64 = ((uint64_t)i << 32) | (uint32_t)(i + 1);
        qpci_memwrite(dev, bar, HYP_ARG_BASE + i * 8, &val64, sizeof(val64));
    }
    /* Read back and verify */
    for (int i = 0; i < HYP_ARG_COUNT; i++) {
        val64 = 0;
        qpci_memread(dev, bar, HYP_ARG_BASE + i * 8, &val64, sizeof(val64));
        g_assert_cmphex(val64, ==, ((uint64_t)i << 32) | (uint32_t)(i + 1));
    }

    g_free(dev);
    qpci_free_pc(pcibus);
    qtest_quit(qts);
}

static void test_hypback_signals(void) {
    uint32_t val32;

    QTestState* qts = qtest_init("-device hypback,addr=04.0");
    QPCIBus* pcibus = qpci_new_pc(qts, NULL);
    QPCIDevice* dev = qpci_device_find(pcibus, QPCI_DEVFN(0x4, 0x0));
    g_assert_nonnull(dev);
    qpci_device_enable(dev);
    QPCIBar bar = qpci_iomap(dev, 0, NULL);

    /* guest_signal: should start at 0, is read-write */
    val32 = ~0U;
    qpci_memread(dev, bar, HYP_GUEST_SIGNAL, &val32, sizeof(val32));
    g_assert_cmphex(val32, ==, 0x00000000);

    val32 = 0xDEAD0001;
    qpci_memwrite(dev, bar, HYP_GUEST_SIGNAL, &val32, sizeof(val32));
    qpci_memread(dev, bar, HYP_GUEST_SIGNAL, &val32, sizeof(val32));
    g_assert_cmphex(val32, ==, 0xDEAD0001);

    /* host_signal: should start at 0, is read-only from guest */
    val32 = ~0U;
    qpci_memread(dev, bar, HYP_HOST_SIGNAL, &val32, sizeof(val32));
    g_assert_cmphex(val32, ==, 0x00000000);

    /* Writing to host_signal should be ignored (value unchanged) */
    val32 = 0xFFFFFFFF;
    qpci_memwrite(dev, bar, HYP_HOST_SIGNAL, &val32, sizeof(val32));
    qpci_memread(dev, bar, HYP_HOST_SIGNAL, &val32, sizeof(val32));
    g_assert_cmphex(val32, ==, 0x00000000);

    g_free(dev);
    qpci_free_pc(pcibus);
    qtest_quit(qts);
}

static void test_hypback_fence(void) {
    uint32_t val32;
    uint64_t val64;

    QTestState* qts = qtest_init("-device hypback,addr=04.0");
    QPCIBus* pcibus = qpci_new_pc(qts, NULL);
    QPCIDevice* dev = qpci_device_find(pcibus, QPCI_DEVFN(0x4, 0x0));
    g_assert_nonnull(dev);
    qpci_device_enable(dev);
    QPCIBar bar = qpci_iomap(dev, 0, NULL);

    /* Fence starts at 0 */
    val32 = ~0U;
    qpci_memread(dev, bar, HYP_FENCE_LO, &val32, sizeof(val32));
    g_assert_cmphex(val32, ==, 0x00000000);

    val32 = ~0U;
    qpci_memread(dev, bar, HYP_FENCE_HI, &val32, sizeof(val32));
    g_assert_cmphex(val32, ==, 0x00000000);

    /* 8-byte fence read: full 64-bit value at offset 0x0200 */
    val64 = ~0ULL;
    qpci_memread(dev, bar, HYP_FENCE_LO, &val64, sizeof(val64));
    g_assert_cmphex(val64, ==, 0x0000000000000000ULL);

    /* Fence is read-only from guest — writing must be ignored */
    val32 = 0xDEADBEEF;
    qpci_memwrite(dev, bar, HYP_FENCE_LO, &val32, sizeof(val32));
    qpci_memread(dev, bar, HYP_FENCE_LO, &val32, sizeof(val32));
    g_assert_cmphex(val32, ==, 0x00000000);

    g_free(dev);
    qpci_free_pc(pcibus);
    qtest_quit(qts);
}

static void test_hypback_dispatch(void) {
    uint32_t val32;
    uint64_t val64;

    QTestState* qts = qtest_init("-device hypback,addr=04.0");
    QPCIBus* pcibus = qpci_new_pc(qts, NULL);
    QPCIDevice* dev = qpci_device_find(pcibus, QPCI_DEVFN(0x4, 0x0));
    g_assert_nonnull(dev);
    qpci_device_enable(dev);
    QPCIBar bar = qpci_iomap(dev, 0, NULL);

    /* Register a test handler for op 0x1001 via QMP */
    QDict* resp = qtest_qmp(qts, "{'execute': 'x-hypback-register-handler'," " 'arguments': {'op-start': %d, 'op-end': %d}}", 0x1001, 0x1001);
    g_assert_nonnull(resp);
    g_assert(qdict_haskey(resp, "return"));
    qobject_unref(resp);

    /* Write DW0: op=0x1001, len=0 */
    val32 = 0x1001;
    qpci_memwrite(dev, bar, HYP_DOORBELL_DW0, &val32, sizeof(val32));

    /* Write two arguments: arg[0]=0xCAFE, arg[1]=0xBABE */
    val64 = 0xCAFE;
    qpci_memwrite(dev, bar, HYP_ARG_BASE, &val64, sizeof(val64));
    val64 = 0xBABE;
    qpci_memwrite(dev, bar, HYP_ARG_BASE + 8, &val64, sizeof(val64));

    /* Ring doorbell: DW1 = arg_count=2, abi=1 */
    val32 = 0x00020001;
    qpci_memwrite(dev, bar, HYP_DOORBELL_DW1, &val32, sizeof(val32));

    /* Verify the test handler was called:
     *   guest_signal = op = 0x1001
     *   host_signal  = arg_count = 2
     *   fence        = 1
     */
    qpci_memread(dev, bar, HYP_GUEST_SIGNAL, &val32, sizeof(val32));
    g_assert_cmphex(val32, ==, 0x1001);

    qpci_memread(dev, bar, HYP_HOST_SIGNAL, &val32, sizeof(val32));
    g_assert_cmphex(val32, ==, 2);

    qpci_memread(dev, bar, HYP_FENCE_LO, &val64, sizeof(val64));
    g_assert_cmphex(val64, ==, 1);

    /* Second call: same op, different args */
    val32 = 0x1001;
    qpci_memwrite(dev, bar, HYP_DOORBELL_DW0, &val32, sizeof(val32));
    val64 = 0xDEAD;
    qpci_memwrite(dev, bar, HYP_ARG_BASE, &val64, sizeof(val64));
    val32 = 0x00010001; /* arg_count=1 */
    qpci_memwrite(dev, bar, HYP_DOORBELL_DW1, &val32, sizeof(val32));

    qpci_memread(dev, bar, HYP_GUEST_SIGNAL, &val32, sizeof(val32));
    g_assert_cmphex(val32, ==, 0x1001);
    qpci_memread(dev, bar, HYP_HOST_SIGNAL, &val32, sizeof(val32));
    g_assert_cmphex(val32, ==, 1);
    qpci_memread(dev, bar, HYP_FENCE_LO, &val64, sizeof(val64));
    g_assert_cmphex(val64, ==, 2);

    /* Unregister and verify dispatch falls through (no crash) */
    resp = qtest_qmp(qts, "{'execute': 'x-hypback-unregister-handler'," " 'arguments': {'op-start': %d, 'op-end': %d}}", 0x1001, 0x1001);
    g_assert_nonnull(resp);
    g_assert(qdict_haskey(resp, "return"));
    qobject_unref(resp);

    val32 = 0x1001;
    qpci_memwrite(dev, bar, HYP_DOORBELL_DW0, &val32, sizeof(val32));
    val32 = 0x00000001;
    qpci_memwrite(dev, bar, HYP_DOORBELL_DW1, &val32, sizeof(val32));
    /* Fence unchanged (no handler registered) */
    qpci_memread(dev, bar, HYP_FENCE_LO, &val64, sizeof(val64));
    g_assert_cmphex(val64, ==, 2);

    g_free(dev);
    qpci_free_pc(pcibus);
    qtest_quit(qts);
}

int main(int argc, char** argv) {
    g_test_init(&argc, &argv, NULL);

    qtest_add_func("/hypback/pci-identity", test_hypback_pci_identity);
    qtest_add_func("/hypback/doorbell", test_hypback_doorbell);
    qtest_add_func("/hypback/arguments", test_hypback_arguments);
    qtest_add_func("/hypback/signals", test_hypback_signals);
    qtest_add_func("/hypback/fence", test_hypback_fence);
    qtest_add_func("/hypback/dispatch", test_hypback_dispatch);

    return g_test_run();
}
