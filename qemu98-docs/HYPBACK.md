# HYPBACK.md — Win9x Hypercall Backdoor PCI Device

> **Status:** Implemented (T2.1 ✅, T2.2 ✅). Source: `hw/misc/hypback.c`, `include/hw/misc/hypback.h`.
>
> **Audience:** Contributors building features that use hypercalls (Voodoo3, audio,
> clipboard, shared folders, future Glide/D3D renderers), and the Win9x VxD
> developer who needs to know the exact BAR0 layout.

---

## 0. TL;DR

The hypback device is a **PCI device with a single 64K MMIO BAR** that lets a
Win9x guest ring-0 VxD send hypercalls to QEMU. The guest writes a hypercall
packet (op code + arguments) into BAR0, then writes the doorbell register
(offset 0x0004) to wake up QEMU. QEMU dispatches to the registered handler for
that op code range, processes the work, increments a 64-bit fence counter, and
optionally fires an MSI interrupt so the guest knows it's done.

```
                    Guest (Win9x)                          Host (QEMU)
                    ──────────────                         ────────────
ring-3 game → DLL shim
                    ↓ IOCTL
ring-0 VxD → writes BAR0 (args + op)
           → writes DW1 @ 0x0004  ────PCI MMIO trap────→  hypback_mmio_write()
                                                          hypback_dispatch()
                                                            ↓
                                                          handler (Glide/D3D/FS/…)
                                                            ↓ increments fence
                                                            ↓ msi_notify()  ←── NEW (T2.2)
                    ← polls fence @ 0x0200 ←───────────
                    ← or MSI interrupt    ←───────────  (if available)
```

---

## 1. PCI Identity

| Field     | Value              | Notes                          |
|-----------|--------------------|--------------------------------|
| Vendor ID | `0x1234`           | `PCI_VENDOR_ID_QEMU`           |
| Device ID | `0xBEEF`           | "HypBack" — looks like `beef`  |
| Revision  | `1`                | Initial ABI version            |
| Class     | `PCI_CLASS_OTHERS` | `0xFFFF` (miscellaneous)       |
| Subsystem | (none)             | Single-function, no sub-vendor |

**lspci -nn output (inside guest):**
```
00:04.0 Class 00ff: 1234:beef (rev 01)
```

---

## 2. BAR0 Memory Map (64 KiB)

```
Offset    Size      Name            Access   Description
──────────────────────────────────────────────────────────────────────
0x0000    4 B       DW0             RW       op[15:0] | len[31:16]
0x0004    4 B       DW1             RW       arg_count[23:16] | flags[15:8] | abi[7:0]
                                             *** WRITING THIS RINGS THE DOORBELL ***
──────────────────────────────────────────────────────────────────────
0x0008    256 B     args[0..31]     RW       32 × 64-bit hypercall arguments
0x0108    4 B       guest_signal    RW       Guest→host signal mask
0x010C    4 B       host_signal     RO       Host→guest signal mask
0x0110    240 B     —               —        Padding (reserved)
──────────────────────────────────────────────────────────────────────
0x0200    8 B       fence           RO       64-bit monotonic completion counter
                                             Read 4 B at 0x0200 for lo, 0x0204 for hi
                                             Read 8 B at 0x0200 for full 64-bit fence
0x0208    3072 B    log_ring[96]    —        Reserved: 96 entries × 32 B each
0x0E08    504 B     —               —        Padding
──────────────────────────────────────────────────────────────────────
0x1000    48 KiB    DMA heap        —        Guest-controlled (not managed by device)
```

### 2.1 DW0 — Operation Code + Length

```
Bits        Field        Description
────────────────────────────────────────
15:0        op           Hypercall operation code (see §4)
31:16       len          Total payload length in bytes (future use)
```

### 2.2 DW1 — Argument Count + Flags + ABI Version

```
Bits        Field        Description
────────────────────────────────────────
7:0         abi          HYP_ABI_VERSION (currently 1)
15:8        flags        Per-call flags (reserved, must be 0)
23:16       arg_count    Number of 64-bit arguments (0..32)
31:24       —            Reserved
```

### 2.3 Argument Region (0x0008–0x0107)

32 slots of 8 bytes each. The guest writes arguments sequentially starting
at offset 0x0008. Both 4-byte (DWORD) and 8-byte (QWORD) writes are supported.
The device uses proper masking so a 4-byte write at offset 0x000C only updates
bytes 4-7 of args[0], preserving bytes 0-3.

| Slot | Offset | Access                   |
|------|--------|--------------------------|
| 0    | 0x0008 | lo 4 B, hi 4 B at 0x000C |
| 1    | 0x0010 | lo 4 B, hi 4 B at 0x0014 |
| …    | …      | …                        |
| 31   | 0x0100 | lo 4 B, hi 4 B at 0x0104 |

### 2.4 Signal Masks (0x0108, 0x010C)

| Register     | Offset | Access | Purpose                        |
|--------------|--------|--------|--------------------------------|
| guest_signal | 0x0108 | RW     | Guest sets bits to signal host |
| host_signal  | 0x010C | RO     | Host sets bits to signal guest |

Currently informational — future host-side services may use these for
asynchronous event delivery.

### 2.5 Completion Fence (0x0200)

A 64-bit monotonic counter. The host handler increments it atomically after
processing each hypercall. The guest can either poll this to detect completion,
or use MSI interrupts (see §2.6).

```asm
; Win9x VxD pseudocode — poll fence after doorbell write
    mov     edx, [hbe_bar + 4]     ; write DW1 (rings doorbell)
    mov     eax, [hbe_bar + 0x200] ; read fence_lo
.poll:
    cmp     eax, [hbe_bar + 0x200]
    je      .poll                  ; spin until fence changes
```

The fence starts at 0 on device reset and increments by 1 per completed call.
Handlers should use `qatomic_inc_fetch(fence)` to increment.

### 2.6 MSI Interrupt Support

The hypback device now supports MSI (Message Signalled Interrupts) as an
alternative to fence polling for hypercall completion notification.
MSI is automatically enabled when the machine type supports it; if
unavailable (e.g., older machine types), the device falls back to
poll-only operation silently.

- **MSI vector:** 0 (single interrupt, edge-triggered)
- **Fired after:** handler completes and increments fence
- **Guest-side:** The VxD driver (`guest-tools/vxd/hypback.asm`) detects
  MSI capability via PCI capabilities walk and registers a VPICD handler.
- **Interrupt pin:** `PCI_INTERRUPT_PIN` is set to 1 (for INTx fallback
  when MSI is not available).
- **64-bit MSI:** supported (4th parameter to `msi_init` is `true`).
- **Per-vector mask:** disabled (5th parameter is `false`).

The VxD checks MSI availability during `Device_Init` and uses the event-based
path when present; otherwise it falls back to spin-with-yield fence polling.

---

## 3. Hypercall Flow

### 3.1 Guest-side protocol (VxD → QEMU)

1. **Write arguments:** The VxD writes 64-bit argument values into `args[0..N-1]`
   at offsets `0x0008 + i*8`. Use DWORD writes for each 32-bit half.
2. **Write DW0:** Write the operation code into DW0 at offset `0x0000`.
   `mov [bar+0], (op | (total_len << 16))`
3. **Ring doorbell:** Write DW1 at offset `0x0004`. This triggers the MMIO
   trap and QEMU dispatches the hypercall.
   `mov [bar+4], (arg_count << 16) | (flags << 8) | ABI_VERSION`
4. **Poll fence:** Read the fence at offset `0x0200`. Spin until the value
   changes (indicating completion), then extract the result from `args[]`
   if the hypercall has output values.

### 3.2 Host-side dispatch (QEMU internal)

When DW1 is written (offset 0x0004), `hypback_mmio_write` calls
`hypback_dispatch()` which:

1. Extracts `op` from DW0 and `arg_count` from DW1
2. Iterates the global handler table (registered via `hypback_register_handler`)
3. Calls the matching handler with `(opaque, op, arg_count, args, &fence)`
4. The handler processes the call and increments `fence`
5. **If MSI is enabled**, fires `msi_notify()` to interrupt the guest VxD

The dispatch runs under the BQL (iothread mutex), so handlers can safely
access QEMU state.

---

## 4. Operation Codes

Op codes are organized in ranges by subsystem:

### Glide3x (0x1000–0x1FFF)

| Code   | Name                       | Description                 | Tier |
|--------|----------------------------|-----------------------------|------|
| 0x1001 | `HYP_GLIDE_TEX_UPLOAD`     | Upload texture to host VRAM | T3   |
| 0x1002 | `HYP_GLIDE_TEX_SETPALETTE` | Set texture palette         | T3   |
| 0x1003 | `HYP_GLIDE_BUFFER_SWAP`    | Swap front/back buffers     | T3   |
| 0x1004 | `HYP_GLIDE_VERTEX_SUBMIT`  | Submit vertex batch         | T3   |

### Direct3D (0x2000–0x2FFF)

| Code   | Name                 | Description        | Tier |
|--------|----------------------|--------------------|------|
| 0x2001 | `HYP_D3D_TEX_UPLOAD` | Upload D3D texture | T3c  |
| 0x2002 | `HYP_D3D_DRAW_PRIM`  | Draw primitive     | T3c  |
| 0x2003 | `HYP_D3D_PRESENT`    | Present frame      | T3c  |

### Filesystem / Shared Folders (0x3000–0x3FFF)

| Code   | Name             | Description            | Tier |
|--------|------------------|------------------------|------|
| 0x3001 | `HYP_FS_OPEN`    | Open file on host      | T4   |
| 0x3002 | `HYP_FS_READ`    | Read from host file    | T4   |
| 0x3003 | `HYP_FS_WRITE`   | Write to host file     | T4   |
| 0x3004 | `HYP_FS_CLOSE`   | Close host file        | T4   |
| 0x3005 | `HYP_FS_READDIR` | Read directory listing | T4   |

### Clipboard (0x4000–0x4FFF)

| Code   | Name                | Description                   | Tier |
|--------|---------------------|-------------------------------|------|
| 0x4001 | `HYP_CLIPBOARD_OUT` | Copy guest clipboard to host  | T4   |
| 0x4002 | `HYP_CLIPBOARD_IN`  | Paste host clipboard to guest | T4   |

### Audio (0x5000–0x5FFF)

| Code   | Name             | Description       | Tier |
|--------|------------------|-------------------|------|
| 0x5001 | `HYP_AUDIO_PLAY` | Play audio buffer | T4   |
| 0x5002 | `HYP_AUDIO_MIDI` | Send MIDI event   | T4   |

New subsystems should claim a 0x1000-aligned range and add defines to
`include/hw/misc/hypback.h`.

---

## 5. Handler Registration API

QEMU-side modules (Voodoo3, renderer, audio, FS) register handlers during
their module initialization:

```c
#include "hw/misc/hypback.h"

typedef struct MyState {
    /* … */
} MyState;

static void my_glide_handler(void *opaque, uint32_t op,
                             uint32_t arg_count, const uint64_t *args,
                             uint64_t *fence)
{
    MyState *s = opaque;

    switch (op) {
    case HYP_GLIDE_TEX_UPLOAD:
        /* args[0] = texture_id, args[1] = dma_addr, args[2] = size */
        handle_tex_upload(s, args[0], args[1], args[2]);
        break;
    /* … */
    }

    /* Signal completion */
    qatomic_inc_fetch(fence);
}

static void my_module_init(void)
{
    /* Register for Glide op code range */
    if (!hypback_register_handler(HYP_GLIDE_TEX_UPLOAD,
                                  HYP_GLIDE_BUFFER_SWAP,
                                  my_glide_handler, my_state)) {
        error_report("my_module: failed to register hypback handler");
    }
}
```

**Constraints:**
- Maximum 8 registered handlers (global limit)
- Op ranges must not overlap
- Handlers are called under BQL
- Handlers must increment `*fence` atomically before returning
- Registration typically happens during `type_init()` or device `realize()`

---

## 6. Usage

### 6.0 Guest tools ISO

The guest tools (VxD driver, test harness) are distributed as a bootable
ISO via the `--enable-guest-tools` configure option. See `BUILD.md` §3.1
for build requirements.

```bash
# Enable guest tools build
../configure --enable-guest-tools
make -j$(nproc)
# ISO is at build/guest-tools/guest-tools.iso
```

Attach the ISO to the Win9x guest to install drivers and tests:
```bash
qemu-system-i386 -device hypback,id=hbe0 -cdrom build/guest-tools/guest-tools.iso
```

### 6.1 Enable the device

```bash
qemu-system-i386 -device hypback,id=hbe0
```

The device is always available — `CONFIG_HYPBACK` defaults to `y` when
`PCI_DEVICES` is enabled.

### 6.2 Verify it's present

```bash
# From host
./qemu-system-i386 -device help 2>&1 | grep hypback

# From guest (after boot)
lspci -nn | grep 1234:beef
```

### 6.3 Register a handler via QMP

```bash
# Start QEMU with QMP
qemu-system-i386 -device hypback,id=hbe0 -qmp unix:/tmp/qmp.sock,server=on,wait=off -M pc -m 16 -nographic

# In another terminal, connect and register a handler:
echo '{ "execute": "qmp_capabilities" }' | socat - UNIX-CONNECT:/tmp/qmp.sock
echo '{ "execute": "x-hypback-register-handler", "arguments": { "op-start": 4097, "op-end": 4097 } }' | socat - UNIX-CONNECT:/tmp/qmp.sock
# Returns: {"return": {}}

# Now any MMIO write of op 0x1001 to BAR0 will trigger the test handler
```

### 6.4 Run the qtest (6 tests including dispatch)

```bash
cd build
meson test --suite qtest-i386 hypback-test
# or:
QTEST_QEMU_BINARY=./qemu-system-i386 tests/qtest/hypback-test --tap -k
```

---

## 7. Design Decisions

### 7.1 Why polled completion instead of IRQ?

~~Win9x PCI IRQ routing through the i440FX/PIIX3 is compatible with
standard PCI IRQs, but polling the fence is simpler for v1:~~

**Updated (T2.2):** MSI interrupt support is now implemented.
The device fires an MSI after each handler completes, and the VxD
uses event-based (MSI) completion when available. The fence polling
path remains as a fallback for guests without MSI support.

- MSI eliminates CPU spin-wasting during hypercall wait.
- The VxD automatically detects MSI via PCI capability walk.
- INTx fallback is available if MSI is unavailable on the machine type.

### 7.2 Why DW1 triggers the doorbell (not DW0)?
The two-step protocol (write DW0 with op, then DW1 with args+flags) lets
the guest set up all arguments and the op code before ringing the doorbell.
This avoids a race where QEMU reads partially-written state. The VxD writes
DW0 last among the two because the op code is determined after arguments
are marshaled.

### 7.3 Why sub-8-byte MMIO access support?
The Win9x VxD runs in x86 ring-0 and naturally uses DWORD (4-byte) MOV
instructions. Supporting both 4-byte and 8-byte accesses at any offset
within the 64-bit argument slots means the VxD can write args[0].lo at
offset 0x0008 and args[0].hi at offset 0x000C with natural DWORD writes,
without needing special QWORD handling.

### 7.4 Why no interrupt pin?

The device now sets `PCI_INTERRUPT_PIN = 1` (added in T2.2) for
INTx fallback. MSI is the primary interrupt mechanism; INTx is
the fallback when MSI is unavailable on the machine type.
The VxD prefers MSI when detected, falling back to fence polling.

---

## 8. Files

| File                                        | Purpose                                           |
|---------------------------------------------|---------------------------------------------------|
| `include/hw/misc/hypback.h`                 | Hypercall ABI, op codes, handler registration API |
| `hw/misc/hypback.c`                         | PCI device implementation (~280 LOC, MSI support) |
| `hw/misc/meson.build`                       | Added `hypback.c` under `CONFIG_HYPBACK`          |
| `hw/misc/Kconfig`                           | `config HYPBACK` (depends on PCI + MSI_NONBROKEN) |
| `tests/qtest/hypback-test.c`                | qtest: MMIO reads/writes, argument region, fence  |
| `tests/qtest/meson.build`                   | Added `hypback-test` to i386/x86_64 test suites   |
| `guest-tools/vxd/hypback.asm`               | Win9x VxD guest driver (~1050 LOC MASM)           |
| `guest-tools/vxd/hypback.def`               | VxD export definitions                            |
| `guest-tools/vxd/makefile`                  | Build with JWasm + MSVC Link                      |
| `guest-tools/vxd/README.md`                 | VxD build/install/usage docs                      |
| `guest-tools/vxd/BUILD_VXD.BAT`             | Guest-side VxD build & install script             |
| `guest-tools/vxd/README_VXD.TXT`            | Guest-side compilation instructions               |
| `guest-tools/vxd/tools/uasm/`               | Bundled UASM assembler (JWasm successor)          |
| `guest-tools/test/test_hypercall.c`         | Win9x smoke test harness                          |
| `guest-tools/test/makefile`                 | Build test harness with MinGW                     |
| `guest-tools/build-guest-tools.sh`          | Cross-build script producing guest-tools.iso      |
| `guest-tools/meson.build`                   | Meson integration for guest-tools ISO target      |
| `guest-tools/README.md`                     | Guest tools overview                              |
| `tests/guest-tools/test-guest-tools-iso.sh` | Integration test for ISO build                    |
| `tests/guest-tools/test-vm-cdrom.sh`        | VM-level test: boots QEMU with ISO as CD-ROM      |
| `tests/guest-tools/meson.build`             | Test wiring for guest-tools ISO verification      |
| `qemu98-docs/WIN9X_QEMU_PLAN.md`            | §5.2.1 — design spec, §6.3 — patch list           |
| `qemu98-docs/BUILD.md`                      | §4.7 — verification, §6 — baseline items          |

---

## 9. References

- **`hw/misc/edu.c`** — pattern reference (single BAR MMIO doorbell)
- **`hw/misc/pvpanic-pci.c`** — simpler PCI device pattern (single function)
- **`WIN9X_QEMU_PLAN.md`** §5.2.1 — original design spec
- **`WIN9X_QEMU_PLAN.md`** §5.3.2 — hypercall protocol layout
- **`WIN9X_QEMU_PLAN.md`** §7.3 — ABI versioning strategy
