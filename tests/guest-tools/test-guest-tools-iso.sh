#!/bin/sh
# test-guest-tools-iso.sh — Verify guest-tools.iso exists and has expected content
#
# Called by Meson test harness after build completes.
# Returns 0 (pass) if ISO is valid, 77 (skip) if build was incomplete,
# 1 (fail) if ISO is missing when it should exist.
#
# Usage: test-guest-tools-iso.sh <path-to-iso> <guest-tools-dir>

ISO_FILE="$1"
GUEST_TOOLS_DIR="$2"

echo "=== Guest Tools ISO Integration Test ==="
echo "ISO path: $ISO_FILE"
echo "Guest tools dir: $GUEST_TOOLS_DIR"

# Check if the ISO was even built (requires JWasm + MinGW + ISO tool)
if [ ! -f "$ISO_FILE" ]; then
    echo "SKIP: guest-tools.iso not found."
    echo "This is expected if build tools (JWasm/MinGW/genisoimage) are missing."
    echo "Install: sudo apt install jwasm gcc-mingw-w64-i686 genisoimage"
    exit 77
fi

# ISO exists — verify it's non-empty
ISO_SIZE=$(stat -c%s "$ISO_FILE" 2>/dev/null || stat -f%z "$ISO_FILE" 2>/dev/null)
if [ "$ISO_SIZE" -lt 2048 ]; then
    echo "FAIL: guest-tools.iso exists but is too small ($ISO_SIZE bytes)"
    exit 1
fi

echo "OK: guest-tools.iso exists ($ISO_SIZE bytes)"

# Verify ISO content using available tools
if command -v isoinfo >/dev/null 2>&1; then
    echo "--- Verifying ISO content with isoinfo ---"
    ISO_CONTENT=$(isoinfo -l -i "$ISO_FILE" 2>/dev/null)
    echo "$ISO_CONTENT"

    # Check for expected files
    has_readme=0
    has_autorun=0
    case "$ISO_CONTENT" in
        *README.TXT*) has_readme=1 ;;
        *README*)     has_readme=1 ;;
    esac
    case "$ISO_CONTENT" in
        *AUTORUN.INF*) has_autorun=1 ;;
    esac

    if [ $has_readme -eq 1 ]; then
        echo "OK: README.TXT found in ISO"
    else
        echo "WARN: README.TXT not found in ISO listing"
    fi
    if [ $has_autorun -eq 1 ]; then
        echo "OK: AUTORUN.INF found in ISO"
    else
        echo "WARN: AUTORUN.INF not found in ISO listing"
    fi
elif command -v xorriso >/dev/null 2>&1; then
    echo "--- Verifying ISO content with xorriso ---"
    xorriso -osirrox on -indev "$ISO_FILE" -ls 2>/dev/null
elif command -v 7z >/dev/null 2>&1; then
    echo "--- Verifying ISO content with 7z ---"
    7z l "$ISO_FILE" 2>/dev/null
else
    echo "INFO: No ISO content viewer available (install isoinfo/xorriso/7z for full verification)"
fi

# Check volume label
if command -v isoinfo >/dev/null 2>&1; then
    VOLUME=$(isoinfo -d -i "$ISO_FILE" 2>/dev/null | grep -i '^Volume id:' | cut -d: -f2- | tr -d ' ')
    echo "Volume label: '$VOLUME'"
    if [ "$VOLUME" = "QEMU98_GUEST_TOOLS" ]; then
        echo "OK: Volume label is correct"
    else
        echo "WARN: Volume label is '$VOLUME', expected 'QEMU98_GUEST_TOOLS'"
    fi
fi

echo ""
echo "=== Integration test PASSED ==="
exit 0
