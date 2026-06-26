OPTION WIN64:3
OPTION LITERALS:ON

WINDOWS64 equ 1
LINUX64   equ 3
OSX64     equ 4

;======================================================================
; WINDOWS x64 types, libs and includes
;======================================================================
IF @Platform EQ WINDOWS64
	includelib c:\jwasm\wininc\lib64\kernel32.lib
	ExitProcess proto :dword
	option  dllimport:<msvcrt>
	printf  proto :ptr, :vararg
	exit    proto :dword
	option  dllimport:none	
	CPRINTF EQU printf
	SYS_EXIT = 0

;======================================================================
; LINUX x64 types, libs and includes
;======================================================================
ELSEIF @Platform EQ LINUX64
	printf proto systemv :PTR, :VARARG
	CPRINTF EQU printf
	SYS_EXIT = 60

;======================================================================
; LINUX x64 types, libs and includes
;======================================================================
ELSEIF @Platform EQ OSX64
	_printf proto systemv :PTR, :VARARG
	CPRINTF EQU _printf
	SYS_EXIT = 0x2000001
ENDIF