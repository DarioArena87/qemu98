# test_hypercall Makefile — Win9x HypBack VxD Smoke Test
#
# Build with MinGW cross-compiler (i686-w64-mingw32-gcc)
# Output runs inside a Win9x guest with HYPBACK.VXD loaded.
#
# Usage:
#   make                    → build test_hypercall.exe
#   make clean              → remove build artifacts

CC       = i686-w64-mingw32-gcc
CFLAGS   = -mconsole -Wall -Wextra -O2
LDFLAGS  = -mconsole
LDLIBS   = -lkernel32 -luser32

all: test_hypercall.exe

test_hypercall.exe: test_hypercall.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $< $(LDLIBS)

clean:
	rm -f test_hypercall.exe

.PHONY: all clean
