QEMU98 Guest Tools — VxD Driver Installation
============================================

This directory contains the HypBack VxD driver source and build tools.
The VxD must be compiled ON the Win9x guest — it cannot be cross-compiled
from Linux because the DDK segment model requires a Win9x-hosted assembler.

QUICK START (if you have the DDK installed):
  1. Open a DOS prompt (MS-DOS Prompt from Start Menu)
  2. Insert or mount this CD-ROM (e.g., drive D:)
  3. Run:  D:\VXD\BUILD_VXD.BAT
  4. Reboot Windows

FILES IN THIS DIRECTORY:
  hypback.asm      — VxD driver source (~550 LOC MASM)
  hypback.def      — VxD export definitions (for linker)
  BUILD_VXD.BAT    — Build script (detects assembler, compiles, installs)
  tools/uasm/      — Bundled UASM assembler (open-source MASM clone)
  makefile         — GNU Make build (for manual use)
  README.md        — Detailed VxD architecture documentation

REQUIRED TOOLS:

  ASSEMBLER (included on this CD):
    UASM 2.57 is bundled at VXD\tools\uasm\UASM32.EXE — no download needed!
    UASM is the actively maintained successor to JWasm, fully MASM-compatible.

  DDK HEADERS (NOT included — must be installed separately):
    The Microsoft Win9x DDK headers (vmm.inc, vpicd.inc, shell.inc)
    are required for compilation. These come with the Microsoft DDK.
    Install the DDK to C:\DDK\ (or use SET DDK_PATH=C:\MYDDK to
    specify a custom location).

  If DDK is not available, you can also use:
  1. Microsoft Visual C++ 6.0 with MASM (ML.EXE in PATH)
  2. Separate JWasm installation (C:\JWASM\JWASM.EXE)

IF YOU DON'T HAVE THE DDK HEADERS:
  - The DDK was distributed with MSDN subscriptions and on CD-ROM
  - Search for "Windows 98 DDK" or "Windows 98 Driver Development Kit"
  - Some Win9x power toys and system packs include DDK components
  - The DDK headers cannot be redistributed (proprietary Microsoft)

INSTALLATION STEPS (manual, if BUILD_VXD.BAT fails):
  1. Assemble:   ML -c -coff -I<DDK_INC_PATH> -FoHYPBACK.OBJ hypback.asm
  2. Link:       LINK /VXD /NODEFAULTLIB /DEF:hypback.def /OUT:HYPBACK.VXD HYPBACK.OBJ
  3. Copy:       copy HYPBACK.VXD C:\WINDOWS\SYSTEM\VMM32\
  4. Configure:  Add "device=HYPBACK.VXD" to [386Enh] in C:\WINDOWS\SYSTEM.INI
  5. Reboot:     Restart Windows to load the driver

VERIFY THE DRIVER IS LOADED:
  1. Go to Control Panel → System → Device Manager
  2. Look for "HypBack" or "QEMU98 Hypercall Backdoor" under System Devices
  3. Or run TEST_HYP.EXE from the root of this CD-ROM:
       D:\TEST_HYP.EXE
  4. Expected output: "HYPBACK: Device found" or similar

TROUBLESHOOTING:
  - "Missing vmm.inc": Ensure DDK headers are installed and -I path is correct
  - "Cannot create VXD": Check free disk space and write permissions
  - "Driver not loading": Check SYSTEM.INI syntax, remove any trailing spaces
  - "Test fails": Ensure QEMU was launched with -device hypback,id=hbe0
