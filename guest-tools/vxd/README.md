# HYPBACK.VXD — Win9x HypBack Guest Driver

> **Status:** Tier 2.2 — Implemented.  ~550 LOC MASM.
>
> **Audience:** Contributors building Win9x guest tools (DLL shims, installer)
> or developers debugging the hypback hypercall protocol from the guest side.

---

## Overview

`HYPBACK.VXD` is a Win9x ring-0 driver (Virtual xDevice) that communicates
with the QEMU hypback PCI device (vendor `0x1234`, device `0xBEEF`).
It provides a hypercall transport layer through which ring-3 DLL shims
(Glide3x, DirectDraw, Direct3D) can offload GPU, audio, clipboard, and
filesystem operations to the QEMU host.

### What It Does

1. **PCI Discovery** — scans the PCI bus for the hypback device, reads BAR0
2. **BAR0 MMIO Mapping** — maps the 64 KiB BAR0 into VxD linear address space
3. **Hypercall Protocol** — writes args + op + doorbell, waits for fence/MSI
4. **MSI Interrupt** — if available, receives MSI completion interrupts
5. **Fence Polling** — fallback when MSI is unavailable (spin-with-yield)
6. **Named Service** — exports `Hypback_Send_Hypercall` for fast ring-3 use
7. **IOCTL Interface** — `DeviceIoControl(path="\\\\.\\HYPBACK.VXD", ...)`

---

## Architecture

```
Ring-3 DLL (glide3x-shim.dll)
        ↓ IOCTL / named service
Ring-0 VxD (HYPBACK.VXD)
        ↓ MMIO writes to BAR0
QEMU hypback PCI device (hw/misc/hypback.c)
        ↓ dispatch to registered handler
QEMU handler (voodoo3, renderer, audio, etc.)
        ↓ increments fence + fires MSI
        ↓
VxD MSI handler → signals completion event
        ↓
Ring-3 DLL gets result from args[]
```

---

## BAR0 Layout (must match include/hw/misc/hypback.h)

```
Offset    Size   Register        Access   Description
0x0000    4 B    DW0             RW       op[15:0] | len[31:16]
0x0004    4 B    DW1             RW       arg_count|flags|abi — WRITE DOORBELL
0x0008    256 B  args[0..31]     RW       32 × 64-bit arguments
0x0108    4 B    guest_signal    RW       Guest→host signal mask
0x010C    4 B    host_signal     RO       Host→guest signal mask
0x0200    8 B    fence           RO       64-bit monotonic completion counter
```

---

## Build Requirements

| Tool      | Version      | Purpose                   |
|-----------|--------------|---------------------------|
| JWasm     | ≥ 2.12       | MASM-compatible assembler |
| MSVC Link | 6.0 or later | LE executable linker      |
| Win9x DDK | Any          | VMM/VPICD headers         |

### Building

```cmd
REM Set up environment
set DDK_INC=C:\ddk\inc

REM Build
make -f makefile
```

Output: `HYPBACK.VXD` (~8–12 KB LE executable)

### Installing in a Win9x Guest

1. Copy `HYPBACK.VXD` to `C:\WINDOWS\SYSTEM\VMM32\`
2. Add to `C:\WINDOWS\SYSTEM.INI` under `[386Enh]`:
   ```ini
   device=HYPBACK.VXD
   ```
3. Reboot the guest
4. Verify: run `test_hypercall.exe` from `guest-tools/test/`

---

## Ring-3 Usage

### Via Named VxD Service (fast path)

```c
// In a Win9x ring-3 application:
#include <windows.h>

BOOL WINAPI HypbackSendHypercall(
    DWORD  op,        // hypercall op code
    DWORD  arg_count, // number of 64-bit args (0..32)
    UINT64 *args      // in/out: 64-bit argument array
);
```

The DLL shim calls this function (declared in `glide3x-shim/` or `ddraw-shim/`).
The VxD maps the call through `Hypback_API_Handler` service 0.

### Via DeviceIoControl (standard path)

```c
HANDLE hHypback = CreateFile("\\\\.\\HYPBACK.VXD", 0, 0, NULL, 0,
                              FILE_FLAG_DELETE_ON_CLOSE, NULL);

// Send a hypercall
struct {
    DWORD op;
    DWORD arg_count;
    UINT64 args[32];
} hc = { .op = 0x1001, .arg_count = 2, .args = { 0x42, 0x1337 } };

DWORD bytesReturned;
DeviceIoControl(hHypback, IOCTL_HYPBACK_SEND,
                &hc, sizeof(hc), &hc, sizeof(hc),
                &bytesReturned, NULL);

CloseHandle(hHypback);
```

---

## Files

| File          | Purpose                      |
|---------------|------------------------------|
| `hypback.asm` | Main VxD source (~550 LOC)   |
| `hypback.def` | Export definitions           |
| `makefile`    | Build with JWasm + MSVC Link |
| `README.md`   | This file                    |

---

## Protocol Reference

See `qemu98-docs/HYPBACK.md` for the full hypercall ABI, op code ranges,
and BAR0 register definitions. The VxD is the QEMU-side BAR0 layout's
**canonical guest writer** — all op codes and offsets must match
`include/hw/misc/hypback.h` exactly.

### ABI Versioning

The VxD uses `HYP_ABI_VERSION = 1`. If the QEMU host increments the ABI,
the VxD must be rebuilt with updated constants. Version mismatch between
VxD and host is detected via the ABI byte in DW1.
