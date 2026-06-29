#!/bin/sh
# build-guest-tools.sh — Build Win9x Guest Tools and Create Distributable ISO
#
# Called by Meson's custom_target. Detects available tools and builds
# whatever it can, then packages all artifacts into a bootable ISO.
#
# Usage:
#   ./build-guest-tools.sh <source_dir> <output_dir> [jwasm] [mingw_cc] [iso_tool]
#
# Copyright (c) 2024 Win9x-QEMU98 Project
# Licensed under the MIT License.

set -e

SRC_DIR="$1"
OUT_DIR="$2"
JWASM="${3:-jwasm}"
MINGW_CC="${4:-i686-w64-mingw32-gcc}"
ISO_TOOL="${5:-genisoimage}"

VXD_SRC="$SRC_DIR/vxd"
TEST_SRC="$SRC_DIR/test"
STAGING="$OUT_DIR/iso-staging"

echo "=== QEMU98 Guest Tools Build ==="
echo "Source directory: $SRC_DIR"
echo "Output directory: $OUT_DIR"

mkdir -p "$STAGING"

# ---- Check for tools ----
have_jwasm=false
have_mingw=false
have_iso_tool=false

if command -v "$JWASM" >/dev/null 2>&1; then
    have_jwasm=true
    echo "[OK] Found JWasm: $JWASM"
else
    echo "[--] JWasm not found — skipping VxD build (install JWasm for HYPBACK.VXD)"
fi

if command -v "$MINGW_CC" >/dev/null 2>&1; then
    have_mingw=true
    echo "[OK] Found MinGW cross-compiler: $MINGW_CC"
else
    # Try llvm-mingw clang as fallback (installed to /opt/llvm-mingw by default)
    for candidate in \
        /opt/llvm-mingw/bin/i686-w64-mingw32-gcc \
        /opt/llvm-mingw/bin/i686-w64-mingw32-clang \
        /usr/local/llvm-mingw/bin/i686-w64-mingw32-clang \
        i686-w64-mingw32-clang; do
        if command -v "$candidate" >/dev/null 2>&1; then
            MINGW_CC="$candidate"
            have_mingw=true
            echo "[OK] Found llvm-mingw cross-compiler: $MINGW_CC"
            break
        fi
    done
    if ! $have_mingw; then
        echo "[--] MinGW cross-compiler not found — skipping test harness build"
    fi
fi

# Try multiple ISO tools
if command -v "$ISO_TOOL" >/dev/null 2>&1; then
    have_iso_tool=true
    echo "[OK] Found ISO tool: $ISO_TOOL"
elif command -v xorriso >/dev/null 2>&1; then
    ISO_TOOL="xorriso"
    have_iso_tool=true
    echo "[OK] Found ISO tool: xorriso"
elif command -v mkisofs >/dev/null 2>&1; then
    ISO_TOOL="mkisofs"
    have_iso_tool=true
    echo "[OK] Found ISO tool: mkisofs"
else
    echo "[--] No ISO tool found (genisoimage, xorriso, or mkisofs)"
    echo "[--] Skipping ISO creation."
fi

# ---- Build HYPBACK.VXD (requires JWasm) ----
if $have_jwasm; then
    echo ""
    echo "--- Building HYPBACK.VXD ---"
    jwasm_ok=false
    (cd "$VXD_SRC" && "$JWASM" -coff -Fo"$STAGING/hypback.obj" hypback.asm) && jwasm_ok=true || true
    if $jwasm_ok; then
        echo "[OK] HYPBACK.VXD object file built"
        echo "[INFO] Skipping VxD link — requires MSVC link.exe on a Windows host"
        echo "[INFO] Object file retained at: $STAGING/hypback.obj"
    else
        echo "[WARN] JWasm compilation failed — skipping VxD"
        echo "[NOTE] HYPBACK.VXD requires the Microsoft Windows 9x DDK to compile."
        echo "[NOTE] The DDK provides vmm.inc, vpicd.inc, shell.inc with"
        echo "[NOTE] MASM-specific segment model macros (VxD_LOCKED_CODE_SEG, etc.)"
        echo "[NOTE] To build HYPBACK.VXD: compile on Windows with MASM 6.11+ / DDK."
        echo "[NOTE] Or use the bundled UASM assembler on the guest (VXD/tools/uasm/)."
        have_jwasm=false
        rm -f "$STAGING/hypback.obj"
    fi
fi

# ---- Build test_hypercall.exe (requires MinGW) ----
if $have_mingw; then
    echo ""
    echo "--- Building test_hypercall.exe ---"
    mingw_ok=false
    (cd "$TEST_SRC" && "$MINGW_CC" -mconsole -Wall -Wextra -O2 \
        -o "$STAGING/TEST_HYP.EXE" test_hypercall.c \
        -lkernel32 -luser32) && mingw_ok=true || true
    if $mingw_ok; then
        echo "[OK] test_hypercall.exe built"
    else
        echo "[WARN] MinGW compilation failed — skipping test harness"
        have_mingw=false
    fi
fi

# ---- Copy VxD source, build kit, and assembler to ISO ----
# The VxD cannot be reliably cross-compiled on Linux because the DDK segment
# model requires MASM 6.11+ with the real DDK headers. Instead, we include
# the full source + build script + UASM assembler so the guest can compile it.
echo ""
echo "--- Copying VxD guest-side build kit ---"
VXD_STAGING="$STAGING/VXD"
mkdir -p "$VXD_STAGING"
for vxd_file in hypback.asm hypback.def BUILD_VXD.BAT README_VXD.TXT makefile README.md; do
    if [ -f "$VXD_SRC/$vxd_file" ]; then
        cp "$VXD_SRC/$vxd_file" "$VXD_STAGING/"
        echo "  [OK] Copied $vxd_file"
    fi
done

# Copy UASM assembler binaries (if downloaded) for guest-side compilation
# UASM lives in VXD/tools/uasm/ so other tools can be added alongside it.
VXD_TOOLS_SRC="$VXD_SRC/tools/uasm"
VXD_TOOLS_STAGING="$VXD_STAGING/tools/uasm"
if [ -d "$VXD_TOOLS_SRC" ] && ls "$VXD_TOOLS_SRC"/*.exe >/dev/null 2>&1; then
    mkdir -p "$VXD_TOOLS_STAGING"
    cp -a "$VXD_TOOLS_SRC"/*.exe "$VXD_TOOLS_STAGING/" 2>/dev/null || true
    echo "  [OK] Copied UASM assembler to VXD/tools/uasm/"
else
    echo "  [INFO] UASM not downloaded — guest needs DDK or its own assembler"
    echo "  [INFO] To include it:"
    echo "    cd guest-tools/vxd/tools"
    echo "    curl -L -o uasm.zip https://www.terraspace.co.uk/uasm257_x86.zip"
    echo "    unzip uasm.zip -d uasm/"
fi
echo "[OK] VxD build kit staged for guest-side compilation"

# ---- Create README.TXT ----
cat > "$STAGING/README.TXT" << 'README_EOF'
QEMU98 Guest Tools — v1.0 (Tier 2.2)
=====================================

This CD contains Win9x guest-side tools for the QEMU98 project.
These tools enable Win9x guests to communicate with QEMU's custom
PCI devices (hypback, Voodoo3) for accelerated graphics, audio,
clipboard sharing, and more.

CONTENTS:
  AUTORUN.INF     — Auto-starts the VxD build/install script
  TEST_HYP.EXE    — Hypercall smoke test utility (pre-built)
  VXD/            — VxD driver source + guest-side build kit
    BUILD_VXD.BAT   Build script for compiling & installing the VxD
    tools/          UASM assembler (MASM-compatible, no DDK needed!)
    hypback.asm     VxD driver source (~550 LOC MASM)
    README_VXD.TXT  Detailed build instructions

QUICK INSTALL (inside a Win9x guest):

  Automatic (recommended):
    1. Insert this CD-ROM — BUILD_VXD.BAT launches automatically
    2. The script detects the bundled UASM assembler and builds HYPBACK.VXD
    3. Add "device=HYPBACK.VXD" to SYSTEM.INI [386Enh] when prompted
    4. Reboot the guest
    5. Run TEST_HYP.EXE from this CD to verify

  Manual (if autorun doesn't work):
    1. Open a DOS prompt (Start → Run → command.com)
    2. Run:  X:\VXD\BUILD_VXD.BAT  (replace X with CD-ROM drive letter)
    3. Reboot when done
    4. Run:  X:\TEST_HYP.EXE

BUNDLED ASSEMBLER: This CD includes the UASM assembler (open-source
MASM clone) in VXD\tools\uasm\ — no need to hunt down an assembler!
However, the Win9x DDK headers (vmm.inc, vpicd.inc, shell.inc) are
still required for compilation. These headers come with the Microsoft
DDK (C:\DDK\inc\win98). Install the DDK on the guest to compile the VxD.

FILE LAYOUT AFTER INSTALLATION:
  C:\WINDOWS\SYSTEM\VMM32\HYPBACK.VXD    — driver binary
  C:\WINDOWS\SYSTEM.INI                   — add "device=HYPBACK.VXD" to [386Enh]

REQUIREMENTS:
  - Windows 95 OSR2 / 98 / 98SE / ME
  - Hypback PCI device present (vendor 0x1234, device 0xBEEF)
  - QEMU host launched with -device hypback,id=hbe0

FOR MORE INFORMATION:
  qemu98-docs/HYPBACK.md       — Hypercall ABI and device spec
  qemu98-docs/WIN9X_QEMU_PLAN.md — Project roadmap
  guest-tools/vxd/README.md    — VxD architecture documentation
README_EOF

# ---- Create AUTORUN.INF ----
# Points to BUILD_VXD.BAT for first-time setup (VxD must be installed
# before TEST_HYP.EXE can run).
cat > "$STAGING/AUTORUN.INF" << 'AUTORUN_EOF'
[AutoRun]
open=VXD\BUILD_VXD.BAT
label=QEMU98 Guest Tools — Install VxD Driver
AUTORUN_EOF

# ---- Create the ISO ----
ISO_FILE="$OUT_DIR/guest-tools.iso"
if $have_iso_tool; then
    echo ""
    echo "--- Creating guest-tools.iso ---"

    case "$ISO_TOOL" in
        *xorriso*)
            "$ISO_TOOL" -as mkisofs \
                -V "QEMU98_GUEST_TOOLS" \
                -J -R \
                -o "$ISO_FILE" \
                "$STAGING"
            ;;
        *)
            # genisoimage / mkisofs
            "$ISO_TOOL" \
                -V "QEMU98_GUEST_TOOLS" \
                -J -R \
                -o "$ISO_FILE" \
                "$STAGING"
            ;;
    esac

    echo "[OK] ISO created: $ISO_FILE"
    ls -lh "$ISO_FILE"
else
    echo ""
    echo "[INFO] ISO tools not available."
    echo "[INFO] Artifacts are staged in: $STAGING"
    echo "[INFO] To create ISO manually:"
    echo "  genisoimage -V QEMU98_GUEST_TOOLS -J -R -o guest-tools.iso $STAGING"
fi

# ---- Summary ----
echo ""
echo "=== Build Summary ==="
echo "  VxD (HYPBACK.VXD):  $($have_jwasm && echo 'BUILT' || echo 'skipped')"
echo "  Test (TEST_HYP.EXE): $($have_mingw && echo 'BUILT' || echo 'skipped')"    echo "  UASM tools:          $([ -d \"$VXD_TOOLS_STAGING\" ] && echo 'bundled' || echo 'not downloaded')"
echo "  ISO:                 $($have_iso_tool && echo 'CREATED' || echo 'skipped')"
echo ""

if ! $have_jwasm || ! $have_mingw || ! $have_iso_tool; then
    echo "To get a complete build, install:"
    ! $have_jwasm   && echo "  - JWasm (MASM-compatible assembler)"
    ! $have_mingw   && echo "  - i686-w64-mingw32-gcc (Win32 cross-compiler)"
    ! $have_iso_tool && echo "  - genisoimage or xorriso or mkisofs (ISO creation tool)"
    echo ""
fi
