; Requires UASM
;written by aw27
.386
.MODEL FLAT, STDCALL
OPTION CASEMAP:NONE
OPTION LITERALS:ON

HANDLE typedef ptr

GENERIC_READ equ 80000000h
FILE_SHARE_READ equ 1 
NULL equ 0
OPEN_EXISTING equ 3
FILE_FLAG_NO_BUFFERING equ 20000000h
INVALID_HANDLE_VALUE equ -1

includelib \masm32\lib\msvcrt.lib
printf proto C :ptr, :vararg
getchar proto C
includelib \masm32\lib\kernel32.lib
CreateFileA proto :ptr, :dword, :dword, :ptr, :dword, :dword, :HANDLE
ReadFile proto :HANDLE, :ptr, :dword, :ptr, :ptr
CloseHandle proto :HANDLE

.code

hexDump proc private uses ebx esi  base:ptr, _len:sdword
	LOCAL buff[17]:byte
	
	mov esi, base
	
	.if _len<=0
		ret
	.endif
	
	.for (ebx=0 : ebx<_len : ebx++) ; Note: .for (ebx=0, ebx<_len, ebx++) crashes Assembler
		.if !(ebx & 0Fh)
			.if (ebx != 0)
				INVOKE printf, "  %s\n", addr buff
			.endif
			INVOKE printf, "  %04x ", ebx
		.endif
		INVOKE printf, " %02x", byte ptr [esi+ebx]

		mov eax, ebx
		and eax, 0Fh
		
		.if (byte ptr [esi+ebx]<20h) || (byte ptr [esi+ebx]>7eh)
			mov byte ptr buff[eax], '.'
		.else
			mov dl, byte ptr [esi+ebx]
			mov byte ptr buff[eax], dl
		.endif
		
		inc eax
		mov byte ptr buff[eax], 0
		
	.endfor
	
	dec eax
	mov ebx, eax

	.while eax!=0
		INVOKE printf, "  "
		inc ebx
		mov eax, ebx
		and eax, 0Fh
	.endw
	INVOKE printf, "  %s\n", addr buff
	
	ret
hexDump endp

main proc
	LOCAL buff[512]:byte
	LOCAL dwBytesRead : dword
	LOCAL hFile : HANDLE
	
	INVOKE CreateFileA, "\\.\PhysicalDrive0",  GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_FLAG_NO_BUFFERING, NULL ; When/if UASM considers \ an escape char filename has to be changed to  \\\\.\\PhysicalDrive0

	.if eax==INVALID_HANDLE_VALUE
		INVOKE printf, "Can't open MBR. Are you launching as Administrator?"
		ret
	.else
		mov hFile, eax
		INVOKE ReadFile, hFile, addr buff, sizeof buff, addr dwBytesRead, NULL
		.if eax==0
			INVOKE printf, "Error reading MBR"
		.else
			INVOKE hexDump, addr buff, sizeof buff
		.endif
	.endif
	INVOKE CloseHandle, hFile
	INVOKE getchar
	ret
	
main endp	

end main