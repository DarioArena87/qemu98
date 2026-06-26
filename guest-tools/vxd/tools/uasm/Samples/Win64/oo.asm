
; OO Testcase 2

; Build with:
;..\uasm64 -win64 -c -Zp8 -Zi -Zd -Zf oo1.asm
;d:\vs2015\vc\bin\link /subsystem:console /machine:x64 /debug /Libpath:"%WINSDK%\v7.1\Lib\x64" oo2.obj

.X64
OPTION CASEMAP:NONE
OPTION STACKBASE:RBP		; RSP or RBP are supported options for the stackbase.
OPTION WIN64:7				; 11/15 for RSP and 1-7 for RBP.
OPTION LITERALS:ON
OPTION VTABLE:ON			; [ON/OFF] dictates whether c-style method invocations use the vtable (slower but method pointers can be modified) or the (faster but fixed) direct invocation.

  	.nolist
    .nocref
	WIN32_LEAN_AND_MEAN equ 1
	_WIN64 				equ 1
    include \wininc\Include\windows.inc
    .list
    .cref
	
    includelib <kernel32.lib>
    includelib <user32.lib>

NormalProc PROTO (real4) a:real4
NormalProc2 PROTO (real4) b:dword, a:real4

;=====================================================================================================================================================
;	
; CLASS Definition inclusion guard.
;
;=====================================================================================================================================================
IFNDEF _CLASS_PERSON_
_CLASS_PERSON_ EQU 1

OINTERFACE Entity
	CVIRTUAL PrintName, <VOIDARG>
	CVIRTUAL SetName, <VOIDARG>, pName:PTR
ENDMETHODS
ENDOINTERFACE

;---------------------------------------------------------------------------------------------------------------
; Define a company class with 1 method and some data.
;---------------------------------------------------------------------------------------------------------------
CLASS Company
    CMETHOD Func
ENDMETHODS
    pName dq 0
ENDCLASS

; A Pointer to Company Object Type.
pCompany TYPEDEF PTR Company

METHOD Company, Init, <VOIDARG>, <>
    ret
ENDMETHOD

METHOD Company, Destroy, <VOIDARG>, <>
    ret
ENDMETHOD

METHOD Company, Func, <real4>, <USES rbx>, input:REAL4
    vmovss xmm0,input
    ret
ENDMETHOD

;---------------------------------------------------------------------------------------------------------------
; Define our Person class with 5 instance methods, 1 static method and 5 member fields.
;---------------------------------------------------------------------------------------------------------------
CLASS Person
	CMETHOD PrintName
	CMETHOD SetName
	CMETHOD Calc
	CMETHOD Calc2
	CMETHOD DoAdd
	CSTATIC IsHuman
ENDMETHODS
	pName   dq 0
	age     db 0
	human   db 0	; static field
	handle  dq 0
    lpComp  pCompany 0
ENDCLASS

; A Pointer to Person Object Type.
pPerson TYPEDEF PTR Person

;---------------------------------------------------------------------------------------------------------------
; Constructor
; Can take optional arguments.
;---------------------------------------------------------------------------------------------------------------
METHOD Person, Init, <VOIDARG>, <USES rbx r10>, age:BYTE, consoleHandle:QWORD, ptrName:PTR
	
	LOCAL isAlive:DWORD
	; Internally the METHOD forms a traditional procedure, so anything that you can do in a PROC you can do in a method.
	
    ; Init the company instance.
    mov rax, _NEW(Company)
    mov rcx,thisPtr
    mov [rcx].lpComp,rax

	; Store console output handle.
	mov rax,consoleHandle
	mov [rcx].handle,rax
	
	; Store pointer to passed in name. 
	; -> The proc arguments conform to calling convention: rcx=thisPtr, dl=age, r8=consoleHandle, r9=ptrName
	mov r9,ptrName
	mov [rcx].pName,r9
	
	; On entry into any method RCX is a pointer to the instance 
	; and the correct reference type is assumed.
	mov [rcx].human, 1					; Hence this is possible.
	mov (Person PTR [rcx]).human, 1		; Alternative forms of reference.
	mov [rcx].Person.human, 1			; " "
	
	mov isAlive,0
	mov al,age
	mov [rcx].age,al
	
	.if( age < 100 )
		mov isAlive,1
	.endif	
	
	; The constructor MUST return it's this pointer in RAX.
	mov rax,thisPtr
	
	ret
ENDMETHOD

;---------------------------------------------------------------------------------------------------------------
; Destructor
; Takes no arguments.
;---------------------------------------------------------------------------------------------------------------
METHOD Person, Destroy, <VOIDARG>, <>
	mov [rcx].age,0
	ret
ENDMETHOD

;---------------------------------------------------------------------------------------------------------------
; Print the persons name to the console.
;---------------------------------------------------------------------------------------------------------------
METHOD Person, PrintName, <VOIDARG>, <USES rbx>
	
	LOCAL bWritten:DWORD
	
	invoke lstrlen,[rcx].pName
	mov r10d,eax

	mov rcx,thisPtr
	mov rax,[rcx].handle
	mov rbx,[rcx].pName
	
	invoke WriteConsole, rax, rbx, r10d, ADDR bWritten, NULL	
	
	ret
ENDMETHOD

;---------------------------------------------------------------------------------------------------------------
; Set person name.
;---------------------------------------------------------------------------------------------------------------
METHOD Person, SetName, <VOIDARG>, <USES rbx>, pNameStr:QWORD

	mov rax,pNameStr
	mov [rcx].pName,rax
	
	ret
ENDMETHOD

;---------------------------------------------------------------------------------------------------------------
; Perform a float calculation, return a dword.
;---------------------------------------------------------------------------------------------------------------
METHOD Person, Calc, <real4>, <USES rbx>, aValue:REAL4

	vmovss xmm0,aValue
	vaddss xmm0,xmm0,FP4(1.0)

	ret
ENDMETHOD

;---------------------------------------------------------------------------------------------------------------
; Perform a calculation on 2 vectors via vectorcall abi.
;---------------------------------------------------------------------------------------------------------------
option stackbase:rsp	; vectorcall currently only supports rsp stackbases.
option win64:11
VECMETHOD Person, Calc2, <VOIDARG>, <USES rbx>, aVec:XMMWORD, bVec:XMMWORD

	ret
ENDMETHOD
option stackbase:rbp
option win64:7

;---------------------------------------------------------------------------------------------------------------
; Perform a calculation on two arguments.
;---------------------------------------------------------------------------------------------------------------
METHOD Person, DoAdd, <dword>, <USES rbx>, aValue:REAL4, bValue:REAL4

	vmovss xmm0,aValue
	vmovss xmm1,bValue
	vaddss xmm0,xmm0,xmm1
	vcvttss2si eax,xmm0

	ret
ENDMETHOD

;---------------------------------------------------------------------------------------------------------------
; Static method to check if a person is a human.
;---------------------------------------------------------------------------------------------------------------
STATICMETHOD Person, IsHuman, <QWORD>, <USES rbx>, somebody:PTR Person

	_STATICREF rax, Person	; Obtain a reference to the static class members
	mov al,(Person PTR [rax]).human
	
	ret
ENDMETHOD

ENDIF

;=====================================================================================================================================================
; END OF PERSON CLASS
;=====================================================================================================================================================
	
.DATA

	hOutput dq 0
	person1 pPerson 0		; A global variable to hold a reference to a Person type.
	
	avgAge REAL4 0			; Integer to real type promotion. (You can use an integer initializer instead of N.n format).
	
    newName db "A new name.. "

.CODE

; -> Using a FRAME PROC as the entry point for both Console and Windows applications is advised to ensure correct stack startup.
MainCRTStartup PROC FRAME
    LOCAL person2:PTR Person	; A local variable to hold a reference to a Person type. (Note you can also use _DECLARE if the Object name includes <>).
    LOCAL ent1:PTR Entity

    invoke GetStdHandle,STD_OUTPUT_HANDLE
    mov hOutput,rax
    
    ; Create two Person instances.
    mov person1, _NEW(Person, 30, hOutput, CSTR("Jane Doe "))
    mov person2, _NEW(Person, 40, hOutput, "Peter Smith ")      ; Use string literals.

;----------------------------------------------------------------------
; TEST CASE 1: Variable Object Pointer, single simple method invocation
;----------------------------------------------------------------------
person1->Calc(2.0)

;----------------------------------------------------------------------
; TEST CASE 2: Variable Object Pointer, double de-reference simple method invocation
;----------------------------------------------------------------------
person1->lpComp->Func(2.0)

;----------------------------------------------------------------------
; TEST CASE 3: Indirect Register, simple method invocation
;----------------------------------------------------------------------
assume rsi:PTR Person
lea rsi,person1
[rsi]->Calc(3.0)
assume rsi:nothing

;----------------------------------------------------------------------
; TEST CASE 4: Indirect Register, double de-reference.
;----------------------------------------------------------------------
assume rsi:PTR Person
lea rsi,person1
[rsi]->lpComp->Func(2.0)
assume rsi:nothing

;----------------------------------------------------------------------
; TEST CASE 5: Direct Register, Simple method invocation.
;----------------------------------------------------------------------
assume rsi:PTR Person
mov rsi,person1
rsi->Calc(3.0)
assume rsi:nothing

;----------------------------------------------------------------------
; TEST CASE 6: Direct register, double de-reference.
;----------------------------------------------------------------------
assume rsi:PTR Person
mov rsi,person1
rsi->lpComp->Func(2.0)
assume rsi:nothing

;----------------------------------------------------------------------
; TEST CASE 7: Indirect register with base+index, simple method invocation.
;----------------------------------------------------------------------
assume rsi:PTR Person
lea rsi,person1
xor rax,rax
[rsi+rax]->Calc(3.0)
assume rsi:nothing

    _INVOKE Person, PrintName, person1		; Direct call (Type, Method, arguments)
    _VINVOKE person2, Person, PrintName		; Vtable call (instance, Type, Method)   
    _INVOKE Person, SetName, person1, CSTR("Michael Smith ")
    _INVOKE Person, PrintName, person1		
    
    _INVOKE Person, Calc, person1, 1.0
    _VINVOKE person2, Person, Calc, 1.0
    _INVOKE Person, Calc2, person2, xmm4, xmm5	; Vectorcall based method.

    ; Use return type information.
    .if( _V(person1, Person, Calc, 1.0) == FP4(2.0) )
        xor eax,eax
    .endif

    mov rax, _STATIC(Person, IsHuman, person1)	; Default return type from _STATIC is 64bit integer.

    ; Method invocation via register pointer.    
    lea rsi, person1
    _INVOKE Person, Calc, [rsi], 1.0
    _VINVOKE [rsi], Person, Calc, 1.0
    .if( _V([rsi], Person, Calc, 1.0) == FP4(2.0) )
        xor eax,eax
    .endif

	; Method invocation using c-style calls.
albl:  person1->Calc(1.0)
	person2->Calc(2.0)
    .if( person1->Calc(1.0) == FP4(2.0) )
        xor eax,eax
    .endif

;----------------------------------------------------------------------
; TEST CASE 8: Indirect register, using dot type specifier instead of assume
;----------------------------------------------------------------------		
	lea rsi,person1
	[rsi].Person->Calc(1.0)
    .if( [rsi].Person->Calc(1.0) == FP4(2.0) )
        xor eax,eax
    .endif
	xor rax,rax
	lea rsi,person2
	[rsi+rax].Person->Calc(1.0)
	xor rax,rax
    .if( [rsi+rax].Person->Calc(1.0) == FP4(2.0) )
        xor eax,eax
    .endif

;----------------------------------------------------------------------
; TEST CASE 9: Using Address-Of Operator
;----------------------------------------------------------------------
    person1->SetName(&newName)

;----------------------------------------------------------------------
; TEST CASE 10: VectorCall ABI
;----------------------------------------------------------------------
    person1->Calc2(xmm0,xmm1)

	person1->Calc( person2->Calc(1.0) )		; Pass the typed result of a method call to another method.
	NormalProc( person1->Calc(1.0) )		; Pass the typed result of a method call to a normal procedure.
	person1->Calc( NormalProc(1.0) )		; Pass the typed result of a normal procedure to a method call.
	person2->DoAdd( 1.0, NormalProc(2.0) )	

;----------------------------------------------------------------------
; TEST CASE 11: Access object through an interface type
;----------------------------------------------------------------------
assume rsi:PTR Entity
mov rsi,person1
;rsi->SetName(&newName)
assume rsi:nothing
mov rax,person1
mov ent1,rax
ent1->SetName(&newName)

;----------------------------------------------------------------------
; TEST CASE 12: Access static method both old and new way
;----------------------------------------------------------------------
	_SINVOKE Person, IsHuman, person1
	Person.IsHuman(person1)
	mov rbx,Person.IsHuman(person1) ; User return type
	.if( Person.IsHuman(person1) == 1 ) ; Use static in hll expr
		xor eax,eax
	.endif
	
	; was ERROR in 2.46.5: Only one object invocation per expression
	.if( person1->Calc( person2->Calc(1.0) ) == FP4(1.0) )
		xor eax,eax
	.endif

	; was ERROR in 2.46.5 : Only one object invocation per expression
	.if (person1->Calc(1.0) == person2->Calc(1.0))
		xor eax,eax
	.endif

    ; Delete the objects.
    _DELETE(person1)
    _DELETE(person2)

    ret
MainCRTStartup ENDP

NormalProc PROC (real4) FRAME a:real4
	LOADSS xmm0,1.0
	ret
NormalProc ENDP

NormalProc2 PROC (real4) FRAME b:dword, a:real4
	LOADSS xmm0,1.0
	ret
NormalProc2 ENDP

END MainCRTStartup



