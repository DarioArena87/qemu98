
; Demonstrates a FASM style flat-mode source, ideal for creating boot-sectors and OS pre-kernel 
; code with UASM.

option flat:1
.code

	org 0h

	use16
	
	xor ax,ax
	xor eax,eax
	
	org 100h

var1 dd 10
	
	use32

	xor ax,ax
	xor eax,eax
		
	org 1000h

var2 dd 20
	
	use64
	
	xor ax,ax
	xor eax,eax
	xor rax,rax
	
	