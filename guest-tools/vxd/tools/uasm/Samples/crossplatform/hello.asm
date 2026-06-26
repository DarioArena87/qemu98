; ####################################################################
;
; Fully cross platform 64bit Hello World Sample.
; Uses built-in @Platform to target code-blocks with UASM 2.45
;
; Windows (x64): uasm64 -c -win64 -Zp8 hello.asm
;                link /machine:x64 /subsystem:console /release hello.obj msvcrt.lib
;
; Linux (x64):   uasm -c -elf64 hello.asm
;                gcc -o hello hello.o
;
; OSX (x64):     uasm -c -macho64 hello.asm
;                ld hello.o -e main -lc -o hello_app
;
; ####################################################################

include crossplatform.inc

main    proto 
MyFunc  proto 

.code

main PROC 
	invoke MyFunc	
	IF @Platform EQ WINDOWS64
	   invoke ExitProcess,0
	ELSE
	   mov eax,SYS_EXIT
	   syscall
	ENDIF
	ret
main ENDP

MyFunc PROC
	invoke CPRINTF, "Hello world!\n"
	ret
MyFunc ENDP

end
