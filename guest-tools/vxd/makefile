#===============================================================================
#  HYPBACK VXD — Makefile (JWasm + MSVC Linker for Win9x)
#
#  Prerequisites:
#    - JWasm (https://github.com/JWasm/JWasm) — MASM-compatible assembler
#    - Windows 9x DDK or compatible headers (vmm.inc, vpicd.inc, shell.inc)
#    - MSVC 6.0 Linker or compatible (link.exe)
#
#  Build output: HYPBACK.VXD — ready to copy to C:\WINDOWS\SYSTEM\VMM32\
#
#  Usage:
#    make               → build HYPBACK.VXD
#    make clean         → remove build artifacts
#===============================================================================

ASM      = jwasm
LINK     = link
ASMFLAGS = -coff -D?FLAT=1 -I"$(DDK_INC)" -I.
LINKFLAGS = /VXD /NODEFAULTLIB /OUT:$@

# Update this path to your Win9x DDK include directory
DDK_INC  = C:\ddk\inc

OBJS     = hypback.obj

all: HYPBACK.VXD

HYPBACK.VXD: $(OBJS) hypback.def
	$(LINK) $(LINKFLAGS) /DEF:hypback.def $(OBJS)

hypback.obj: hypback.asm
	$(ASM) $(ASMFLAGS) -Fo$@ hypback.asm

clean:
	del /Q $(OBJS) HYPBACK.VXD 2>NUL

.PHONY: all clean
