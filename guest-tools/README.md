# guest-tools/ — Win9x Guest-Side Tools

> **Status:** Tier 2.2 in progress — VxD driver implemented, DLL shims upcoming.
>
> **Audience:** Developers building the Win9x guest tools that ship alongside
> the QEMU98 Win9x fork. These tools are installed inside a Win9x guest VM
> and communicate with the QEMU host through the hypback PCI device.

---

## What Lives Here

This tree contains all Win9x guest-side code — ring-0 drivers (VxDs),
ring-3 DLL shims, and the installer — that enable the guest to talk to
QEMU's custom PCI devices (hypback, Voodoo3).

| Directory       | Type        | Description                                   | Status     |
|-----------------|-------------|-----------------------------------------------|------------|
| `vxd/`          | Ring-0 MASM | HYPBACK.VXD — Hypercall transport driver      | ✅ Done     |
| `test/`         | Win32 C     | `test_hypercall.exe` — VxD smoke test         | ✅ Done     |
| `glide3x-shim/` | Ring-3 C    | Replacement `glide3x.dll` / `glide2x.dll`     | 🚧 Tier 3  |
| `ddraw-shim/`   | Ring-3 C    | Replacement `ddraw.dll` for DDraw-only games  | 🚧 Tier 3  |
| `d3d-shim/`     | Ring-3 C    | Replacement D3D5/6/7 DLLs (deferred)          | 🚧 Tier 3c |
| `lib9p/`        | Ring-3 C    | Win9x 9P client for shared folders (deferred) | 🚧 Tier 4  |
| `installer/`    | NSIS        | End-user installer bundle (deferred)          | 🚧 Tier 4  |

---

## Architecture

```
Ring-3 Application (game.exe)
  ↓ loads glide3x.dll (our shim)
glide3x-shim.dll
  ↓ IOCTL / named service
HYPBACK.VXD (ring-0)
  ↓ MMIO writes to BAR0
QEMU hypback PCI device
  ↓ dispatch to handler
QEMU host renderer / audio / FS handler
```

---

## Build Prerequisites

### For the VxD (ring-0) — Guest-Side Compilation

The VxD requires the Microsoft Windows 9x DDK (MASM 6.11+ with real `vmm.inc`,
`vpicd.inc`, `shell.inc` headers) and **cannot** be cross-compiled on Linux.

The ISO distribution includes everything needed to compile on the guest:

| Tool        | Purpose                      | Bundled                        |
|-------------|------------------------------|--------------------------------|
| UASM 2.57   | JWasm successor, MASM-compat | ✅ `VXD/tools/uasm/`            |
| DDK Headers | VMM/VPICD macros             | ❌ must be installed on guest   |
| MSVC Link   | LE executable linker         | ❌ part of DDK or Visual Studio |

### For the test harness (ring-3)

| Tool                 | Purpose               | Platform      |
|----------------------|-----------------------|---------------|
| i686-w64-mingw32-gcc | Win32 cross-compiler  | Linux/Windows |
| MinGW/MSVC           | Native Win32 compiler | Windows       |

### For DLL shims (future, ring-3)

| Tool                 | Purpose               | Platform      |
|----------------------|-----------------------|---------------|
| i686-w64-mingw32-gcc | Win32 cross-compiler  | Linux/Windows |
| MSVC 6.0             | Native Win32 compiler | Windows       |

---

## Installing in a Win9x Guest

1. Attach `guest-tools.iso` as CD-ROM (`-cdrom build/guest-tools/guest-tools.iso`)
2. The guest autoruns `BUILD_VXD.BAT` which:
   - Detects the bundled UASM assembler (`VXD\tools\uasm\UASM32.EXE`)
   - Or a system-installed DDK/MASM/Visual Studio
   - Compiles and links `HYPBACK.VXD`
   - Copies it to `C:\WINDOWS\SYSTEM\VMM32\`
3. Add to `C:\WINDOWS\SYSTEM.INI` under `[386Enh]` when prompted:
   ```ini
   device=HYPBACK.VXD
   ```
4. Reboot the guest
5. Run `TEST_HYP.EXE` from the CD-ROM to verify the VxD is working
6. On the host, register a QMP handler:
   ```bash
   echo '{"execute":"x-hypback-register-handler","arguments":{"op-start":4099,"op-end":4099}}' | socat - UNIX-CONNECT:/tmp/qmp.sock
   ```
7. Re-run `TEST_HYP.EXE` — fence should now increment

If the guest doesn't have the DDK installed, see `VXD\README_VXD.TXT` on the
ISO for sourcing the required headers.

---

## Protocol

See `../qemu98-docs/HYPBACK.md` for the full hypercall ABI.
All offsets, op codes, and field encodings are defined in
`../include/hw/misc/hypback.h` (host side) and duplicated as
constants in `vxd/hypback.asm` (guest side).

---

## File Layout

```
guest-tools/
├── README.md                 ← This file
├── vxd/
│   ├── hypback.asm           ← Main VxD source (~1050 LOC)
│   ├── hypback.def           ← VxD exports
│   ├── makefile               ← JWasm + MSVC Link build
│   ├── BUILD_VXD.BAT          ← Guest-side build & install script
│   ├── README_VXD.TXT         ← Guest-side compilation instructions
│   ├── README.md              ← VxD developer docs
│   └── tools/uasm/            ← Bundled UASM assembler (JWasm successor)
├── test/
│   ├── test_hypercall.c      ← Win32 smoke test harness
│   └── makefile               ← MinGW cross-compile build
├── glide3x-shim/              (future — Tier 3.1)
├── ddraw-shim/                (future — Tier 3.2)
├── d3d-shim/                  (future — Tier 3c)
├── lib9p/                     (future — Tier 4)
└── installer/                 (future — Tier 4)
```
