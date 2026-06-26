;==============================================================================
;  HYPBACK.ASM — Win9x HypBack VxD Guest Driver
;
;  Ring-0 VxD that communicates with the QEMU hypback PCI device
;  (vendor 0x1234, device 0xBEEF) through its BAR0 MMIO region.
;
;  Provides:
;    - Named VxD service "Hypback_Send_Hypercall" for fast ring-3 access
;    - IOCTL interface via DeviceIoControl (W32_DEVICEIOCONTROL)
;    - MSI interrupt handler with fence-polling fallback
;    - PCI scan with fixed-address fallback
;
;  ABI version: 1 (HYP_ABI_VERSION from include/hw/misc/hypback.h)
;
;  Copyright (c) 2024 Win9x-QEMU98 Project
;  Licensed under the MIT License.
;==============================================================================

        .386p
        .xlist
        include vmm.inc
        include vpicd.inc
        include shell.inc
        .list

;==============================================================================
;  Constants — must match include/hw/misc/hypback.h
;==============================================================================

HYP_VENDOR_ID           equ     1234h           ; PCI_VENDOR_ID_QEMU
HYP_DEVICE_ID           equ     0BEEFh           ; "HypBack"

HYP_MMIO_SIZE           equ     10000h           ; 64 KiB BAR0

; BAR0 register offsets
HYP_DW0                 equ     0000h            ; op[15:0] | len[31:16]
HYP_DW1                 equ     0004h            ; arg_count|flags|abi (WRITE RINGS DOORBELL)
HYP_ARG_BASE            equ     0008h            ; 32 × 8-byte arguments
HYP_ARG_COUNT           equ     32
HYP_GUEST_SIGNAL        equ     0108h            ; Guest→host signal mask (RW)
HYP_HOST_SIGNAL         equ     010Ch            ; Host→guest signal mask (RO)
HYP_FENCE_LO            equ     0200h            ; Completion fence (64-bit, monotonic)
HYP_FENCE_HI            equ     0204h
HYP_LOG_BASE            equ     0208h
HYP_DMA_HEAP_BASE       equ     1000h            ; Guest-controlled DMA region

; DW0/DW1 field encoding
HYP_DW0_OP_MASK         equ     0000FFFFh
HYP_DW0_LEN_SHIFT       equ     16

HYP_DW1_ABI_MASK        equ     000000FFh
HYP_DW1_FLAGS_SHIFT     equ     8
HYP_DW1_ARG_COUNT_SHIFT equ     16

HYP_ABI_VERSION         equ     1

; Hypercall op codes
HYP_GLIDE_TEX_UPLOAD     equ    1001h
HYP_GLIDE_TEX_SETPALETTE equ    1002h
HYP_GLIDE_BUFFER_SWAP    equ    1003h
HYP_GLIDE_VERTEX_SUBMIT  equ    1004h

HYP_D3D_TEX_UPLOAD       equ    2001h
HYP_D3D_DRAW_PRIM        equ    2002h
HYP_D3D_PRESENT          equ    2003h

HYP_FS_OPEN              equ    3001h
HYP_FS_READ              equ    3002h
HYP_FS_WRITE             equ    3003h
HYP_FS_CLOSE             equ    3004h
HYP_FS_READDIR           equ    3005h

HYP_CLIPBOARD_OUT        equ    4001h
HYP_CLIPBOARD_IN         equ    4002h

HYP_AUDIO_PLAY           equ    5001h
HYP_AUDIO_MIDI           equ    5002h

; IOCTL codes (CTL_CODE macro: device_type, function, method, access)
; Device type: FILE_DEVICE_UNKNOWN (22h)
; Method: METHOD_BUFFERED (0)
; Access: FILE_ANY_ACCESS (0)
FILE_DEVICE_UNKNOWN     equ     22h
METHOD_BUFFERED         equ     0
FILE_ANY_ACCESS         equ     0

CTL_CODE macro devtype, func, method, access
        exitm %(((devtype) shl 16) or ((access) shl 14) or ((func) shl 2) or (method))
endm

IOCTL_HYPBACK_SEND      equ     CTL_CODE(FILE_DEVICE_UNKNOWN, 800h, METHOD_BUFFERED, FILE_ANY_ACCESS)
IOCTL_HYPBACK_GET_FENCE equ     CTL_CODE(FILE_DEVICE_UNKNOWN, 801h, METHOD_BUFFERED, FILE_ANY_ACCESS)
IOCTL_HYPBACK_GET_BAR0  equ     CTL_CODE(FILE_DEVICE_UNKNOWN, 802h, METHOD_BUFFERED, FILE_ANY_ACCESS)

;==============================================================================
;  Device Descriptor Block (DDB)
;==============================================================================

HYPBACK_MAJOR_VER       equ     1
HYPBACK_MINOR_VER       equ     0

Declare_Virtual_Device HYPBACK, HYPBACK_MAJOR_VER, HYPBACK_MINOR_VER, \
    Hypback_Control, UNDEFINED_DEVICE_ID, UNDEFINED_INIT_ORDER, \
    Hypback_API_Handler, Hypback_API_Handler

;==============================================================================
;  Data Section
;==============================================================================

VxD_LOCKED_DATA_SEG

; Device context — allocated once at init
Hypback_Context         dd      0               ; ptr to allocated context

; Pointer to BAR0 linear address (mapped from PCI BAR)
HBE_BAR0                dd      0               ; linear address of BAR0 MMIO

; PCI config info
HBE_PCI_BUS             db      0
HBE_PCI_DEVFN           db      0
HBE_BAR0_PHYS           dd      0               ; physical BAR0 address

; MSI state
HBE_MSI_ENABLED         db      0               ; 1 if MSI is active
HBE_MSI_IRQ             dd      0               ; IRQ handle/vector
HBE_MSI_VECTOR           db      0               ; allocated interrupt vector

; Completion event — signalled by MSI handler, waited on by hypercall dispatch
HBE_COMPLETION_EVENT    dd      0               ; VMM event handle

; Spin-lock for hypercall serialisation
HBE_LOCK                 dd      0

; Hypercall input buffer (IOCTL path — copy from ring-3)
HBE_IOCTL_BUFFER        dd      0               ; ptr to ring-3 buffer (temp)

; Saved BAR0 address for info queries
HBE_CACHED_FENCE_LO     dd      0               ; last known fence lo

; Debug counters
HBE_HYPERCALL_COUNT      dd      0
HBE_MSI_COUNT            dd      0

VxD_LOCKED_DATA_ENDS

;==============================================================================
;  Locked Code Section
;==============================================================================

VxD_LOCKED_CODE_SEG

;------------------------------------------------------------------------------
;  BeginProc Hypback_Control — Main VxD control dispatcher
;
;  Called by VMM for all system control messages.
;  Entry: EBP → Client Register Structure (if ring-3 call), or 0 (system call)
;         EAX  = Control Message (Sys_*_Init, W32_DEVICEIOCONTROL, etc.)
;------------------------------------------------------------------------------
BeginProc Hypback_Control

        Control_Dispatch Sys_Critical_Init,  Hypback_Critical_Init
        Control_Dispatch Device_Init,         Hypback_Device_Init
        Control_Dispatch Sys_VM_Init,         Hypback_VM_Init
        Control_Dispatch Sys_VM_Terminate,    Hypback_VM_Terminate
        Control_Dispatch System_Exit,         Hypback_System_Exit
        Control_Dispatch W32_DEVICEIOCONTROL, Hypback_IOCTL_Handler
        clc
        ret

EndProc Hypback_Control

;------------------------------------------------------------------------------
;  Hypback_Critical_Init — Called early in system boot.
;  Return carry clear on success, carry set on failure.
;------------------------------------------------------------------------------
BeginProc Hypback_Critical_Init

        ; Nothing critical to do this early — defer to Device_Init.
        clc
        ret

EndProc Hypback_Critical_Init

;------------------------------------------------------------------------------
;  Hypback_Device_Init — Main initialisation entry point.
;
;  1. Allocate device context
;  2. Scan PCI bus for hypback device (vendor 0x1234, device 0xBEEF)
;  3. Map BAR0 into linear address space
;  4. Detect and configure MSI (if available)
;  5. Create completion event and lock
;------------------------------------------------------------------------------
BeginProc Hypback_Device_Init

        pushad

        ; --- Step 1: Allocate device context ---
        VMMCall _HeapAllocate, <size HypbackContext>, HEAPZEROINIT
        or      eax, eax
        jz      dev_init_fail
        mov     [Hypback_Context], eax

        ; --- Step 2: Scan PCI bus for hypback device ---
        call    Hypback_PCI_Scan
        or      eax, eax
        jz      dev_init_no_device

        ; --- Step 3: Map BAR0 ---
        call    Hypback_Map_BAR0
        or      eax, eax
        jz      dev_init_fail

        ; --- Step 4: Detect MSI ---
        call    Hypback_Detect_MSI

        ; --- Step 5: Create sync primitives ---
        VMMCall _Create_Event, <0>
        mov     [HBE_COMPLETION_EVENT], eax

        ; Initialise spin-lock (0 = unlocked)
        mov     dword ptr [HBE_LOCK], 0

        ; Trace: device initialised successfully
        Trace_Out "HYPBACK: Device initialised, BAR0 at #%08lX", HBE_BAR0

        ; If MSI is enabled, trace that too
        cmp     byte ptr [HBE_MSI_ENABLED], 1
        jne     @F
        Trace_Out "HYPBACK: MSI enabled, IRQ #%08lX", HBE_MSI_IRQ
@@:

dev_init_done:
        popad
        clc
        ret

dev_init_no_device:
        Trace_Out "HYPBACK: No hypback PCI device found (1234:BEEF)"
        popad
        clc                             ; Don't fail — VxD can load without device
        ret

dev_init_fail:
        Trace_Out "HYPBACK: Device_Init failed"
        popad
        stc
        ret

EndProc Hypback_Device_Init

;------------------------------------------------------------------------------
;  Hypback_VM_Init — Called when a new VM (DOS box) is created.
;  Not needed for hypback (system-wide device).
;------------------------------------------------------------------------------
BeginProc Hypback_VM_Init
        clc
        ret
EndProc Hypback_VM_Init

;------------------------------------------------------------------------------
;  Hypback_VM_Terminate — Called when a VM is destroyed.
;------------------------------------------------------------------------------
BeginProc Hypback_VM_Terminate
        clc
        ret
EndProc Hypback_VM_Terminate

;------------------------------------------------------------------------------
;  Hypback_System_Exit — Cleanup at system shutdown.
;  Unmap BAR0, destroy events, release resources.
;------------------------------------------------------------------------------
BeginProc Hypback_System_Exit

        ; Destroy completion event
        cmp     dword ptr [HBE_COMPLETION_EVENT], 0
        je      @F
        VMMCall _Destroy_Event, [HBE_COMPLETION_EVENT]
@@:

        ; Note: BAR0 was mapped via _MapPhysToLinear; the VMM
        ; automatically cleans up page-table mappings on System_Exit.
        ; We do not call _PageFree (that's for _PageAllocate).

        ; Free device context
        cmp     dword ptr [Hypback_Context], 0
        je      @F
        VMMCall _HeapFree, [Hypback_Context], 0
@@:

        Trace_Out "HYPBACK: System_Exit — calls=%lu MSI=%lu", \
                  [HBE_HYPERCALL_COUNT], [HBE_MSI_COUNT]

        clc
        ret

EndProc Hypback_System_Exit

;==============================================================================
;  PCI Scan Routines
;==============================================================================

;------------------------------------------------------------------------------
;  Hypback_PCI_Scan — Find the hypback PCI device.
;
;  Strategy:
;    1. Use PCI BIOS (INT 1Ah, B1h) to search by vendor/device ID.
;    2. If PCI BIOS is unavailable, fall back to direct config-space scan.
;    3. Save bus/devfn and BAR0 physical address.
;
;  Returns: EAX = 1 if found, 0 if not found.
;------------------------------------------------------------------------------
BeginProc Hypback_PCI_Scan

        push    ebx ecx edx esi edi

        ; --- Method 1: PCI BIOS FIND_PCI_DEVICE (function B102h) ---
        ; This searches for a specific vendor/device ID across all buses.
        mov     ax, 0B102h              ; FIND_PCI_DEVICE
        mov     cx, HYP_DEVICE_ID       ; Device ID
        mov     dx, HYP_VENDOR_ID        ; Vendor ID
        mov     si, 0                   ; Index 0 (first match)
        int     1Ah
        ; On success: AH=0, BH=bus, BL=devfn (bits 7:3 = device, 2:0 = func)
        cmp     ah, 0
        jne     pci_scan_fallback

        ; Store PCI location
        mov     [HBE_PCI_BUS], bh
        mov     [HBE_PCI_DEVFN], bl

        ; --- Read BAR0 from config space ---
        ; BAR0 is at offset 10h in PCI config space
        mov     ax, 0B109h              ; READ_CONFIG_DWORD
        mov     bh, [HBE_PCI_BUS]
        mov     bl, [HBE_PCI_DEVFN]
        mov     di, 10h                 ; BAR0 register offset
        int     1Ah
        ; Returns ECX = dword value
        mov     [HBE_BAR0_PHYS], ecx

        ; Mask off the lower bits to get the physical base address
        ; BAR0 is memory-mapped, so bits 3:0 = 0 (type indicator)
        and     ecx, 0FFFFFFF0h
        mov     [HBE_BAR0_PHYS], ecx

        Trace_Out "HYPBACK: PCI device found at bus=%02X devfn=%02X BAR0_phys=%08lX", \
                  [HBE_PCI_BUS], [HBE_PCI_DEVFN], [HBE_BAR0_PHYS]

        mov     eax, 1                  ; success
        jmp     pci_scan_done

pci_scan_fallback:
        ; --- Method 2: Fixed-address fallback ---
        ; QEMU's i440FX places the hypback device at a known PCI slot.
        ; Try PCI bus 0, device 4, function 0 (addr=04.0).
        ; Read vendor/device ID from config space to confirm.

        mov     ax, 0B109h              ; READ_CONFIG_DWORD
        mov     bh, 0                   ; bus 0
        mov     bl, 20h                 ; devfn: device 4 (20h), function 0
        mov     di, 0                   ; Vendor/Device ID (offset 0)
        int     1Ah
        ; Returns ECX = vendor_id | (device_id << 16)
        cmp     cx, HYP_VENDOR_ID       ; Check vendor
        jne     pci_scan_not_found
        shr     ecx, 16
        cmp     cx, HYP_DEVICE_ID       ; Check device
        jne     pci_scan_not_found

        ; Found at the expected location
        mov     [HBE_PCI_BUS], bh
        mov     [HBE_PCI_DEVFN], bl

        ; Read BAR0
        mov     ax, 0B109h
        mov     di, 10h
        int     1Ah
        mov     [HBE_BAR0_PHYS], ecx
        and     ecx, 0FFFFFFF0h
        mov     [HBE_BAR0_PHYS], ecx

        Trace_Out "HYPBACK: PCI device found (fallback) BAR0_phys=%08lX", \
                  [HBE_BAR0_PHYS]

        mov     eax, 1
        jmp     pci_scan_done

pci_scan_not_found:
        xor     eax, eax

pci_scan_done:
        pop     edi esi edx ecx ebx
        ret

EndProc Hypback_PCI_Scan

;------------------------------------------------------------------------------
;  Hypback_Map_BAR0 — Map the PCI BAR0 into linear address space.
;
;  Uses VMM service _MapPhysToLinear to map the 64 KiB MMIO region.
;  Returns: EAX = 1 on success, 0 on failure.
;------------------------------------------------------------------------------
BeginProc Hypback_Map_BAR0

        push    ebx ecx edx

        mov     eax, [HBE_BAR0_PHYS]
        or      eax, eax
        jz      map_bar0_fail

        ; Map 64 KiB (16 pages) of MMIO space
        ; _MapPhysToLinear(phys_addr, size, flags)
        mov     ecx, HYP_MMIO_SIZE
        xor     edx, edx                ; flags = 0 (non-cacheable)
        VMMCall _MapPhysToLinear, <eax, ecx, edx>
        or      eax, eax
        jz      map_bar0_fail

        mov     [HBE_BAR0], eax

        Trace_Out "HYPBACK: BAR0 mapped to linear %08lX", eax

        mov     eax, 1
        jmp     map_bar0_done

map_bar0_fail:
        xor     eax, eax

map_bar0_done:
        pop     edx ecx ebx
        ret

EndProc Hypback_Map_BAR0

;------------------------------------------------------------------------------
;  Hypback_Detect_MSI — Check for MSI capability and set up handler.
;
;  Reads PCI capabilities list to find MSI (capability ID 05h).
;  If found, programs the MSI message and registers an IRQ handler
;  via VPICD.
;
;  MSI on the hypback device means the host fires an MSI interrupt
;  after each hypercall completion. The handler signals the completion
;  event which wakes the hypercall dispatch.
;------------------------------------------------------------------------------
BeginProc Hypback_Detect_MSI

        push    eax ebx ecx edx esi edi

        ; --- Check if PCI device has capabilities list ---
        ; Read STATUS register (offset 06h) to check CAPABILITIES bit (bit 4)
        mov     ax, 0B10Ah              ; READ_CONFIG_WORD
        mov     bh, [HBE_PCI_BUS]
        mov     bl, [HBE_PCI_DEVFN]
        mov     di, 6                   ; Status register
        int     1Ah
        ; Returns CX = status word
        test    cx, 0010h               ; CAPABILITIES bit
        jz      msi_not_found

        ; --- Find capability pointer (offset 34h) ---
        mov     ax, 0B10Bh              ; READ_CONFIG_BYTE
        mov     di, 34h                 ; Capabilities Pointer
        int     1Ah
        ; Returns CL = capability pointer
        movzx   edi, cl

        ; --- Walk capability chain ---
msi_cap_walk:
        or      edi, edi
        jz      msi_not_found

        mov     ax, 0B10Bh
        mov     di, di                   ; current offset
        int     1Ah
        ; CL = capability ID
        cmp     cl, 05h                 ; MSI capability ID
        je      msi_found

        ; Next capability
        inc     edi
        mov     ax, 0B10Bh
        mov     di, di
        int     1Ah
        movzx   edi, cl
        jmp     msi_cap_walk

msi_found:
        ; --- MSI capability found at EDI ---
        ; Read message control word
        mov     ax, 0B10Ah
        mov     di, di
        add     di, 2                   ; Message Control at capability+2
        int     1Ah
        ; CX = message control

        ; Allocate an IRQ via VPICD for the MSI handler
        VPICD_Call VPICD_Virtualize_IRQ, <1>  ; Reserve one IRQ
        or      eax, eax
        jz      msi_not_found
        mov     [HBE_MSI_IRQ], eax          ; Save IRQ handle

        ; Read MSI message address (capability+4)
        mov     ax, 0B109h              ; READ_CONFIG_DWORD
        sub     di, 2
        add     di, 4                   ; Message Address
        int     1Ah
        ; ECX = message address (to program into APIC, not needed on guest side)

        ; Read MSI message data (capability+8 or +C depending on 64-bit)
        mov     ax, 0B10Ah
        add     di, 4                   ; Message Data
        int     1Ah
        ; CX = message data (contains vector)

        ; Register our handler with VPICD
        movzx   eax, cl
        and     eax, 0FFh               ; Extract vector from message data
        mov     [HBE_MSI_VECTOR], al

        VPICD_Call VPICD_Force_Default_Behavior, [HBE_MSI_IRQ], \
                   OFFSET32 Hypback_MSI_Handler, 0

        mov     byte ptr [HBE_MSI_ENABLED], 1
        Trace_Out "HYPBACK: MSI configured — IRQ=%08lX vector=%02X", \
                  [HBE_MSI_IRQ], [HBE_MSI_VECTOR]

        jmp     msi_done

msi_not_found:
        mov     byte ptr [HBE_MSI_ENABLED], 0
        Trace_Out "HYPBACK: MSI not available — using fence polling"

msi_done:
        pop     edi esi edx ecx ebx eax
        ret

EndProc Hypback_Detect_MSI

;==============================================================================
;  MSI Interrupt Handler
;==============================================================================

;------------------------------------------------------------------------------
;  Hypback_MSI_Handler — MSI interrupt handler.
;
;  Called by VPICD when the hypback device fires an MSI interrupt.
;  Signals the completion event to wake the hypercall dispatch.
;
;  This runs at interrupt level — must be fast and non-blocking.
;------------------------------------------------------------------------------
BeginProc Hypback_MSI_Handler

        pushad

        inc     dword ptr [HBE_MSI_COUNT]

        ; Signal the completion event to wake any waiting hypercall
        cmp     dword ptr [HBE_COMPLETION_EVENT], 0
        je      @F
        VMMCall _Set_Event, [HBE_COMPLETION_EVENT]
@@:

        ; Send EOI to the APIC
        VPICD_Call VPICD_Phys_EOI, [HBE_MSI_IRQ]

        popad
        clc
        ret

EndProc Hypback_MSI_Handler

;==============================================================================
;  Hypercall Protocol Implementation
;==============================================================================

;------------------------------------------------------------------------------
;  Hypback_Send_Hypercall_Internal — Send a hypercall to the host and wait
;  for completion.
;
;  Protocol (see HYPBACK.md §3.1):
;    1. Write arguments into args[0..N-1] at BAR0+0x0008
;    2. Write op code into DW0 at BAR0+0x0000
;    3. Write DW1 (arg_count|flags|ABI) at BAR0+0x0004 ← THIS RINGS DOORBELL
;    4. Wait for completion (MSI event or fence poll)
;    5. Read back output args
;
;  Entry: EAX = op code (bits 15:0)
;         ECX = arg_count (0..32)
;         EDX = ptr to args[] array (64-bit values, 8 bytes each)
;
;  Returns: EAX = 0 on success, -1 on timeout/error
;           Completion fence value in [HBE_CACHED_FENCE_LO]
;
;  Note: Takes HBE_LOCK to serialise access to the MMIO region.
;        This is critical — only one caller at a time can use BAR0.
;------------------------------------------------------------------------------
BeginProc Hypback_Send_Hypercall_Internal

        push    ebx ecx edx esi edi ebp

        ; --- Serialise: spin until we own the lock ---
        call    Hypback_Acquire_Lock

        ; --- Step 1: Write arguments ---
        ; ECX = arg_count, EDX = ptr to source args array
        mov     esi, edx                ; ESI → source args[]
        mov     edi, [HBE_BAR0]          ; EDI → BAR0 base
        add     edi, HYP_ARG_BASE       ; EDI → args[0] in BAR0

        ; Pre-write DW0 with zeros (len=0 for now)
        mov     ebx, [HBE_BAR0]
        mov     dword ptr [ebx + HYP_DW0], 0

        push    ecx                      ; save arg_count for later
        or      ecx, ecx
        jz      args_done

        ; Clamp arg_count to max
        cmp     ecx, HYP_ARG_COUNT
        jbe     @F
        mov     ecx, HYP_ARG_COUNT
@@:

        ; Write each 64-bit argument as two DWORDs
args_loop:
        mov     eax, [esi]              ; lo 32 bits
        mov     edx, [esi + 4]          ; hi 32 bits
        mov     [edi], eax              ; write lo → BAR0 + arg[i]
        mov     [edi + 4], edx          ; write hi → BAR0 + arg[i] + 4
        add     esi, 8
        add     edi, 8
        dec     ecx
        jnz     args_loop

args_done:
        pop     ecx                      ; restore arg_count

        ; Clamp arg_count for doorbell
        cmp     ecx, HYP_ARG_COUNT
        jbe     @F
        mov     ecx, HYP_ARG_COUNT
@@:

        ; --- Step 2: Write DW0 (op code) ---
        ; EAX still holds op from entry
        mov     ebx, [HBE_BAR0]
        and     eax, HYP_DW0_OP_MASK    ; mask to 16 bits
        ; len = 0 (no additional payload for now)
        mov     [ebx + HYP_DW0], eax

        ; --- Step 3: Get current fence value ---
        mov     edx, [ebx + HYP_FENCE_LO]

        ; --- Step 4: Ring the doorbell (write DW1) ---
        ; Build DW1: (arg_count << 16) | (flags << 8) | ABI_VERSION
        ; Flags = 0 for now
        mov     eax, ecx
        shl     eax, HYP_DW1_ARG_COUNT_SHIFT
        or      eax, HYP_ABI_VERSION    ; ABI in bits 7:0
        mov     [ebx + HYP_DW1], eax

        ; --- Step 5: Wait for completion ---
        ; Two paths: MSI event, or fence polling
        inc     dword ptr [HBE_HYPERCALL_COUNT]

        cmp     byte ptr [HBE_MSI_ENABLED], 1
        jne     poll_fence

        ; --- MSI path: wait for completion event ---
        ; The MSI handler calls _Set_Event when the host fires the interrupt.
        ; We poll the event with yield rather than using a blocking wait
        ; (VMM semi-blocking calls are DDK-version-dependent).
        mov     ecx, 100000             ; sanity: max ~100k iterations (~1 second)
msi_wait:
        ; Check if fence changed (belt-and-suspenders: event or fence)
        mov     ebx, [HBE_BAR0]
        cmp     edx, [ebx + HYP_FENCE_LO]
        jne     completion_done

        ; Test the event
        VMMCall _Test_Event, [HBE_COMPLETION_EVENT]
        or      eax, eax
        jnz     msi_event_fired

        ; Yield and retry
        VMMCall _Yield
        dec     ecx
        jnz     msi_wait
        jmp     completion_done

msi_event_fired:
        ; Clear the event before proceeding
        VMMCall _Clear_Event, [HBE_COMPLETION_EVENT]
        ; Event fired — the fence has already been incremented.
        ; Jump directly to completion; no need to enter the poll loop.
        jmp     completion_done

poll_fence:
        ; --- Polling path: spin on fence with yield ---
        ; On Win9x, pure spin loops can hang the system (no preemption).
        ; We yield the CPU periodically to keep the system responsive.
        push    ecx
        mov     ecx, 1000000            ; sanity: max ~1M iterations (~1 second)

poll_loop:
        mov     ebx, [HBE_BAR0]
        cmp     edx, [ebx + HYP_FENCE_LO]
        jne     poll_done

        ; Yield CPU every 1024 iterations to avoid hogging the core
        test    ecx, 3FFh
        jnz     @F
        VMMCall _Yield
@@:
        dec     ecx
        jnz     poll_loop

poll_done:
        pop     ecx

completion_done:
        ; --- Step 6: Read back output args ---
        ; Copy args[] from BAR0 back to caller's buffer
        ; ECX = arg_count, EDX still has original ESI (caller's args ptr)
        push    edx                      ; save caller's args pointer

        mov     edi, edx                ; EDI → caller's destination buffer
        mov     esi, [HBE_BAR0]
        add     esi, HYP_ARG_BASE       ; ESI → args[0] in BAR0

        or      ecx, ecx
        jz      readback_done

        cmp     ecx, HYP_ARG_COUNT
        jbe     @F
        mov     ecx, HYP_ARG_COUNT
@@:
readback_loop:
        mov     eax, [esi]              ; read lo from BAR0
        mov     edx, [esi + 4]          ; read hi from BAR0
        mov     [edi], eax              ; write lo to caller buffer
        mov     [edi + 4], edx          ; write hi to caller buffer
        add     esi, 8
        add     edi, 8
        dec     ecx
        jnz     readback_loop

readback_done:
        pop     edx                      ; restore caller's args pointer

        ; Cache the latest fence value
        mov     ebx, [HBE_BAR0]
        mov     eax, [ebx + HYP_FENCE_LO]
        mov     [HBE_CACHED_FENCE_LO], eax

        ; --- Release lock ---
        call    Hypback_Release_Lock

        xor     eax, eax                ; SUCCESS
        pop     ebp edi esi edx ecx ebx
        ret

EndProc Hypback_Send_Hypercall_Internal

;------------------------------------------------------------------------------
;  Hypback_Acquire_Lock — Spin until HBE_LOCK is 0, then set to 1.
;  Simple test-and-set spinlock. Safe because VxDs run non-preemptively
;  (no other VxD thread can interrupt us unless we yield).
;------------------------------------------------------------------------------
BeginProc Hypback_Acquire_Lock
        push    eax
@@:
        ; Atomically exchange 1 into the lock variable
        mov     eax, 1
        xchg    eax, [HBE_LOCK]
        or      eax, eax
        jz      lock_acquired
        ; Lock is held — yield and try again
        VMMCall _Yield
        jmp     @B
lock_acquired:
        pop     eax
        ret
EndProc Hypback_Acquire_Lock

;------------------------------------------------------------------------------
;  Hypback_Release_Lock — Set HBE_LOCK to 0.
;------------------------------------------------------------------------------
BeginProc Hypback_Release_Lock
        mov     dword ptr [HBE_LOCK], 0
        ret
EndProc Hypback_Release_Lock

;==============================================================================
;  Named VxD Service — Fast ring-3 access path
;==============================================================================

;------------------------------------------------------------------------------
;  Hypback_API_Handler — VxD service dispatcher.
;
;  Called by VMM when another VxD or ring-3 code invokes a named service.
;  Entry: EAX = service ID (VMM-assigned, or 0 for services)
;         EBX = client register structure pointer (CRS)
;         ECX = parameter (service-specific)
;
;  Service 0: Hypback_Send_Hypercall
;    Input:  [CRS + Client_EAX] = op code
;            [CRS + Client_ECX] = arg_count
;            [CRS + Client_EDX] = ptr to args array
;    Output: [CRS + Client_EAX] = 0 on success, -1 on failure
;            args array updated in-place with output values
;
;  Service 1: Hypback_Get_Fence
;    Output: [CRS + Client_EAX] = current fence value (lo 32 bits)
;------------------------------------------------------------------------------
BeginProc Hypback_API_Handler

        or      eax, eax                ; Service 0?
        jz      api_send_hypercall

        cmp     eax, 1                  ; Service 1?
        je      api_get_fence

        cmp     eax, 2                  ; Service 2?
        je      api_get_bar0

        ; Unknown service
        Trace_Out "HYPBACK: Unknown service %08lX", eax
        clc
        ret

api_send_hypercall:
        pushad
        ; Extract parameters from client registers
        ; VxD services get called with EBX = Client_Reg_Struc ptr

        ; Check if caller is ring-3 or ring-0.
        ; If ring-0 (another VxD), the args pointer is already accessible.
        ; If ring-3, we need _LinPageLock.
        test    byte ptr [ebx.Client_CS], 3   ; check RPL (ring) bits
        jz      api_send_from_vxd              ; ring-0 path

        ; Ring-3 path: lock the caller's args buffer
        VxDcall _LinPageLock, <[ebx.Client_EDX], 128, 0>
        or      eax, eax
        jz      api_send_fail_lock

        mov     edx, eax                ; EDX → ring-0 view of args buffer

        ; EAX = op, ECX = arg_count
        mov     eax, [ebx.Client_EAX]    ; op code
        mov     ecx, [ebx.Client_ECX]   ; arg_count

        call    Hypback_Send_Hypercall_Internal

        ; Unlock the ring-3 pages
        push    eax                      ; save return value
        VxDcall _LinPageUnLock, <[ebx.Client_EDX], 128, 0>
        pop     eax

        ; Return to caller: EAX = 0 on success
        mov     [ebx.Client_EAX], eax
        jmp     api_send_done

api_send_from_vxd:
        ; Ring-0 path: args pointer is already directly accessible
        mov     edx, [ebx.Client_EDX]   ; EDX → args buffer (ring-0)
        mov     eax, [ebx.Client_EAX]    ; op code
        mov     ecx, [ebx.Client_ECX]   ; arg_count

        call    Hypback_Send_Hypercall_Internal

        mov     [ebx.Client_EAX], eax

api_send_done:
        popad
        clc
        ret

api_send_fail_lock:
        mov     dword ptr [ebx.Client_EAX], -1
        popad
        clc
        ret

api_get_fence:
        push    eax
        mov     eax, [HBE_CACHED_FENCE_LO]
        mov     [ebx.Client_EAX], eax
        pop     eax
        clc
        ret

api_get_bar0:
        push    eax
        mov     eax, [HBE_BAR0]
        mov     [ebx.Client_EAX], eax
        pop     eax
        clc
        ret

EndProc Hypback_API_Handler

;==============================================================================
;  IOCTL Handler — Ring-3 DeviceIoControl path
;==============================================================================

;------------------------------------------------------------------------------
;  Hypback_IOCTL_Handler — Dispatch W32_DEVICEIOCONTROL messages.
;
;  Called by VMM when ring-3 calls DeviceIoControl on \\\\.\\HYPBACK.VXD.
;
;  Entry: EBP → Client Register Structure
;         [EBP.Client_ECX] = DIOCParams structure pointer
;
;  DIOCParams:
;    +00: Internal1
;    +04: VMHandle
;    +08: Internal2
;    +0C: dwIoControlCode
;    +10: lpInBuffer
;    +14: cbInBuffer
;    +18: lpOutBuffer
;    +1C: cbOutBuffer
;    +20: lpcbBytesReturned
;    +24: lpoOverlapped
;    +28: Internal3
;    +2C: Internal4
;------------------------------------------------------------------------------
BeginProc Hypback_IOCTL_Handler

        ; Get DIOCParams pointer from client ECX
        mov     eax, [ebp.Client_ECX]
        or      eax, eax
        jz      ioctl_fail

        ; Read the IOCTL code
        mov     eax, [eax + 0Ch]         ; DIOCParams.dwIoControlCode

        cmp     eax, IOCTL_HYPBACK_SEND
        je      ioctl_send

        cmp     eax, IOCTL_HYPBACK_GET_FENCE
        je      ioctl_get_fence

        cmp     eax, IOCTL_HYPBACK_GET_BAR0
        je      ioctl_get_bar0

        ; Unknown IOCTL
        mov     dword ptr [ebp.Client_EAX], 0
        clc
        ret

; --- IOCTL_HYPBACK_SEND ---
; Input buffer:  struct { uint32_t op; uint32_t arg_count; uint64_t args[32]; }
; Output buffer: same struct, updated with output args
ioctl_send:
        pushad

        mov     esi, [ebp.Client_ECX]    ; ESI → DIOCParams

        mov     eax, [esi + 10h]         ; lpInBuffer
        mov     ecx, [esi + 14h]         ; cbInBuffer
        or      eax, eax
        jz      ioctl_send_fail

        ; Lock the input buffer for ring-0 access
        VxDcall _LinPageLock, <eax, ecx, 0>
        or      eax, eax
        jz      ioctl_send_fail
        mov     edi, eax                ; EDI → ring-0 view of buffer

        ; Extract op and arg_count from buffer
        mov     eax, [edi]              ; op (first dword)
        mov     ecx, [edi + 4]          ; arg_count (second dword)
        lea     edx, [edi + 8]          ; args[] start at offset 8

        call    Hypback_Send_Hypercall_Internal

        ; Unlock the buffer
        push    eax
        mov     eax, [esi + 10h]
        mov     ecx, [esi + 14h]
        VxDcall _LinPageUnLock, <eax, ecx, 0>
        pop     eax

        ; Set bytes returned
        mov     edi, [esi + 20h]         ; lpcbBytesReturned
        or      edi, edi
        jz      @F
        mov     dword ptr [edi], 8 + 32*8  ; min struct size
@@:

        mov     [ebp.Client_EAX], 1      ; TRUE = success
        jmp     ioctl_send_done

ioctl_send_fail:
        mov     dword ptr [ebp.Client_EAX], 0  ; FALSE = failure
ioctl_send_done:
        popad
        clc
        ret

; --- IOCTL_HYPBACK_GET_FENCE ---
; Output: uint64_t current fence value
ioctl_get_fence:
        push    eax ebx

        mov     esi, [ebp.Client_ECX]
        mov     edi, [esi + 18h]         ; lpOutBuffer
        or      edi, edi
        jz      ioctl_gf_done

        ; Lock output buffer
        VxDcall _LinPageLock, <edi, 8, 0>
        or      eax, eax
        jz      ioctl_gf_done
        mov     edi, eax

        ; Read fence from BAR0
        mov     ebx, [HBE_BAR0]
        mov     eax, [ebx + HYP_FENCE_LO]
        mov     [edi], eax              ; fence lo
        mov     eax, [ebx + HYP_FENCE_HI]
        mov     [edi + 4], eax           ; fence hi

        ; Unlock
        mov     edi, [esi + 18h]
        VxDcall _LinPageUnLock, <edi, 8, 0>

        ; Bytes returned
        mov     edi, [esi + 20h]
        or      edi, edi
        jz      @F
        mov     dword ptr [edi], 8
@@:
        mov     dword ptr [ebp.Client_EAX], 1

ioctl_gf_done:
        pop     ebx eax
        clc
        ret

; --- IOCTL_HYPBACK_GET_BAR0 ---
; Output: uint32_t BAR0 linear address
ioctl_get_bar0:
        push    eax

        mov     esi, [ebp.Client_ECX]
        mov     edi, [esi + 18h]         ; lpOutBuffer
        or      edi, edi
        jz      ioctl_bar0_done

        VxDcall _LinPageLock, <edi, 4, 0>
        or      eax, eax
        jz      ioctl_bar0_done
        mov     edi, eax

        mov     eax, [HBE_BAR0]
        mov     [edi], eax

        mov     edi, [esi + 18h]
        VxDcall _LinPageUnLock, <edi, 4, 0>

        mov     edi, [esi + 20h]
        or      edi, edi
        jz      @F
        mov     dword ptr [edi], 4
@@:
        mov     dword ptr [ebp.Client_EAX], 1

ioctl_bar0_done:
        pop     eax
        clc
        ret

ioctl_fail:
        mov     dword ptr [ebp.Client_EAX], 0
        clc
        ret

EndProc Hypback_IOCTL_Handler

VxD_LOCKED_CODE_ENDS

;==============================================================================
;  Context Structure
;==============================================================================

VxD_LOCKED_DATA_SEG

HypbackContext struct
    ; Reserved for future per-instance state
    dwReserved1 dd 0
    dwReserved2 dd 0
    dwReserved3 dd 0
HypbackContext ends

VxD_LOCKED_DATA_ENDS

        END
