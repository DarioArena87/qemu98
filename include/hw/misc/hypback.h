/*
 * Win9x HypBack PCI Device — Hypercall ABI
 *
 * This defines the hypercall operation codes and handler registration
 * interface for the hypback PCI device used by Win9x guests to offload
 * GPU, filesystem, clipboard, and audio operations to the QEMU host.
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

#ifndef HW_MISC_HYPBACK_H
#define HW_MISC_HYPBACK_H

#include "qemu/osdep.h"

/* ------------------------------------------------------------------ */
/*  BAR0 MMIO Layout (64 KiB)                                         */
/* ------------------------------------------------------------------ */
#define HYP_MMIO_SIZE               (64 * KiB)

/* Doorbell region */
#define HYP_DOORBELL_DW0            0x0000  /* op[15:0] | len[31:16] */
#define HYP_DOORBELL_DW1            0x0004  /* arg_count[23:16] | flags[15:8] | abi[7:0] */
#define HYP_ARG_BASE                0x0008  /* 32 args × 8 bytes = 256 bytes */
#define HYP_ARG_COUNT               32

/* Status region */
#define HYP_GUEST_SIGNAL            0x0108  /* guest→host signal mask (RW) */
#define HYP_HOST_SIGNAL             0x010C  /* host→guest signal mask (RO) */

/* Completion fence */
#define HYP_FENCE_LO                0x0200  /* 64-bit monotonic fence counter */
#define HYP_FENCE_HI                0x0204

/* Log ring (96 entries × 32 bytes = 3072 bytes, fits before 0x1000) */
#define HYP_LOG_BASE                0x0208
#define HYP_LOG_ENTRIES             96
#define HYP_LOG_ENTRY_SIZE          32

/* Guest DMA heap (not managed by device — guest VxD maps this area) */
#define HYP_DMA_HEAP_BASE           0x1000

/* ------------------------------------------------------------------ */
/*  Doorbell DW0 field encoding                                       */
/* ------------------------------------------------------------------ */
#define HYP_DW0_OP_MASK             0x0000FFFF
#define HYP_DW0_LEN_MASK            0xFFFF0000
#define HYP_DW0_LEN_SHIFT           16

/* ------------------------------------------------------------------ */
/*  Doorbell DW1 field encoding                                       */
/* ------------------------------------------------------------------ */
#define HYP_DW1_ABI_MASK            0x000000FF
#define HYP_DW1_FLAGS_MASK          0x0000FF00
#define HYP_DW1_FLAGS_SHIFT         8
#define HYP_DW1_ARG_COUNT_MASK      0x00FF0000
#define HYP_DW1_ARG_COUNT_SHIFT     16

#define HYP_ABI_VERSION             1

/* ------------------------------------------------------------------ */
/*  Hypercall Operation Codes                                         */
/* ------------------------------------------------------------------ */

/* Glide3x (0x1000 range) */
#define HYP_GLIDE_TEX_UPLOAD        0x1001
#define HYP_GLIDE_TEX_SETPALETTE    0x1002
#define HYP_GLIDE_BUFFER_SWAP       0x1003
#define HYP_GLIDE_VERTEX_SUBMIT     0x1004

/* Direct3D (0x2000 range) */
#define HYP_D3D_TEX_UPLOAD          0x2001
#define HYP_D3D_DRAW_PRIM           0x2002
#define HYP_D3D_PRESENT             0x2003

/* Filesystem (0x3000 range) */
#define HYP_FS_OPEN                 0x3001
#define HYP_FS_READ                 0x3002
#define HYP_FS_WRITE                0x3003
#define HYP_FS_CLOSE                0x3004
#define HYP_FS_READDIR              0x3005

/* Clipboard (0x4000 range) */
#define HYP_CLIPBOARD_OUT           0x4001
#define HYP_CLIPBOARD_IN            0x4002

/* Audio (0x5000 range) */
#define HYP_AUDIO_PLAY              0x5001
#define HYP_AUDIO_MIDI              0x5002

/* ------------------------------------------------------------------ */
/*  Handler Registration                                              */
/* ------------------------------------------------------------------ */

/**
 * HypbackHandler: callback invoked when the guest writes a hypercall
 * packet and rings the doorbell.
 *
 * @opaque:       opaque pointer registered with the handler
 * @op:           hypercall operation code (HYP_GLIDE_*, HYP_D3D_*, etc.)
 * @arg_count:    number of 64-bit arguments (0..32)
 * @args:         array of 64-bit arguments (length == arg_count)
 * @fence:        pointer to the device's 64-bit completion fence counter;
 *                handler increments this after processing (write atomically)
 */
typedef void (*HypbackHandler)(void* opaque, uint32_t op, uint32_t arg_count, const uint64_t* args, uint64_t* fence);

/**
 * hypback_register_handler: register a handler for a range of op codes.
 *
 * The handler is called under the BQL (iothread mutex) when the guest
 * writes the doorbell with an op code in [op_start, op_end].
 *
 * Only one handler can be registered for a given op code. Returns
 * false if the range overlaps an existing registration.
 */
bool hypback_register_handler(uint32_t op_start, uint32_t op_end, HypbackHandler handler, void* opaque);

/**
 * hypback_unregister_handler: remove a previously registered handler.
 */
void hypback_unregister_handler(uint32_t op_start, uint32_t op_end);

#endif /* HW_MISC_HYPBACK_H */
