; MSX2ANSI ANSI V9938 Library v.1.1
;
; Original Code by Tobias Keizer (ANSI-DRV.BIN)
; Tobias has made this great piece of code and most of what is in it has been
; coded by him
;
; This version of code and conversion into SDCC library by Oduvaldo Pavan Junior
; ducasp@gmail.com
;
; Comercial usage of this code or derivative works of this code are
; allowed ONLY upon agreement with the author.
; Non-comercial usage is free as long as you publish your code changes and give
; credits to the original authors
;
; Changelog:
;
; v1.1: 
; Added ESC[J behavior when no parameter / 0 was choosen (delete from cursor on)
; Added ESC[1J (delete from cursor up to top of screen) and fixed ESC[2J support 
; Fixed behavior when no parameters were given (it was not always correct)
; Added ESC[nP support for Linux telnet daemons

	.area _CODE


;
; C Functions area
;
; In this section, we handle the calls from C code
;


; AnsiInit needs no parameters
;
; Will set the proper screen mode, clear screen, set cursor stuff
;
; You MUST call it, otherwise results might be unpredictable and crash
;
; void AnsiInit()
_AnsiInit::
	PUSH	IX					; Interslot call might mess with IX and C expect it to be intact
	CALL	V9938_Init			; Initialize screen mode, etc
	CALL	V9938_InitCursor	; Initialize cursor and return 
	CALL	V9938_ClearScreen	; Clear screen
	POP	IX						; Restore IX so C won't have issues
	RET


; AnsiFinish needs no parameters
;
; Will restore MSX to Screen 0 and restore original palette
;
; You MUST call it before returning to MSX-DOS, otherwise user will face a 
; static screen and think it has crashed (you can type MODE 80 and restore it
; manually). So MAKE SURE to handle CTRL+BREAK, CTRL+C, etc and call this function
; before returning.
;
; void AnsiFinish()
_AnsiFinish::
	PUSH	IX					; Interslot call might mess with IX and C expect it to be intact
	CALL	V9938_Finish		; Restore	
	POP	IX						; Restore IX so C won't have issues
	RET


; AnsiCallBack - Will call a __z88dk_fastcall function with Column/Line as a parameter 
;
; This is useful to handle quickly ESC[6n cursor position requests, as it is up to
; the user program to determine how to send that information.
;
; void AnsiCallBack(unsigned int uiCallBackAddress) __z88dk_fastcall
_AnsiCallBack::
	LD	(#ANSI_CGP.CALL_VEC + 1),HL	; Load the callback function address
	LD	A,#0x01					
	LD	(#ANSI_CB),A			; Flag that have a callback function
	RET


; AnsiGetCursorPosition - Add possibility to get current cursor position
; unsigned int AnsiGetCursorPosition( )
; LSB will be current Column
; MSB will be current Row
_AnsiGetCursorPosition::
	LD	A,(#CursorCol)			; Get Current Cursor Column Position
	INC	A						; Increment it (internally it is 0-79)
	LD	L,A						; Place column in L
	LD	A,(#CursorRow)			; Get Current Cursor Row (line) Position
	INC	A						; Increment it (internally it is 0-24)
	LD	H,A						; Place row in H
	RET

; AnsiPutChar - will put the char in register L on screen or buffer if part of
; ANSI / VT sequence
;
; void AnsiPutChar(unsigned char ucChar) __z88dk_fastcall
_AnsiPutChar::
	LD	A,L						; Parameter is in L
BufferChar:
	OR	A
	RET	Z						; If 0, no need to print nor ANSI parameter
	LD	C,A						; Save char in C
	LD	A,(#ANSI_M)
	OR	A
	JR	NZ,BufferChar.CNT		; Esc processing going on
	LD	A,C
	CP	#27						; Is character ESC?
	JR	NZ,BufferChar.PRT		; Nope, so print it
	; It is ESC
BufferChar.ESC:	
	LD	(#ANSI_M),A				; Indicate ESC is in progress
	LD	HL,#ANSI_S
	LD	(HL),A					; Save in first buffer position
	INC	HL						; Next buffer position
	LD	(#ANSI_P),HL			; Save in the pointer 
	RET							; Done for now
BufferChar.CNT:	
	LD	HL,(#ANSI_P)			; Current buffer free position
	CP	#27						; was ESC last byte?
	JR	Z,BufferChar.CH2		; Yes, check position 2
	; No
	LD	A,C						; Restore character
	LD	(HL),A					; Store in buffer
	INC	HL
	LD	(#ANSI_P),HL			; new buffer position
	CP	#48
	JR	C,BufferChar.END		; Character is less than '0', not a parameter I understand, so print on the screen
	; No, '0' or greater
	CP	#60				
	JR	NC,BufferChar.END		; If A > ';' not a parameter I understand, so print on the screen
	;Otherwise it is between 0 and ; so ESC command has not finished yet
	RET
BufferChar.END:	
	XOR	A
	LD	(HL),A
	LD	(#ANSI_M),A				; No longer processing
BufferChar.RET:	
	LD	HL,#ANSI_S
	JP	PrintText.RLP			; Ok, print the buffer we did not process
BufferChar.CH2:	
	LD	A,C						; Restore char
	LD	(HL),A					; Store it
	INC	HL						; Increment pointer
	CP	#'['					; Just deal with ESC[ commands, other commands not supported at this moment
	JR	NZ,BufferChar.END		; So if the second character is not [, print the ESC sequence and life goes on
	LD	(#ANSI_M),A				; Ok, now we are gathering parameters for the command
	LD	(#ANSI_P),HL			; Save pointer
	RET							; Done
BufferChar.PRT:	
	LD	(#ANSI_S+0),A			; Put the char in our buffer
	XOR	A				
	LD	(#ANSI_S+1),A			; Now the terminator
	JR	BufferChar.RET			; And print it :-)

; AnsiPrint - will proccess and print the string whose address is in HL (zero terminated)
; void __z88dk_fastcall AnsiPrint(unsigned char * ucString)
_AnsiPrint::
BufferText:
	LD	A,(HL)					; Load the character
	INC	HL						; Increment pointer
	OR 	A						; 0?
	RET	Z						; Yes, end of string
	PUSH	HL					; Save pointer
	CALL	BufferChar			; Process or print it
	POP	HL						; Restore pointer
	JP	BufferText				; Continue
PrintText:
PrintText.RLP:	
	LD	A,(HL)					; Load the character
	INC	HL						; Increment the pointer
	CP	#0x20				
	JP	C,ControlCode			; If less than 0x20 (space), a control character
	PUSH	HL					; Save Pointer
	CALL	V9938_PrintChar		; Call the print routine for our chip
	POP	HL						; Restore Pointer
	LD	A,(#CursorCol)			; Get Current Cursor Position
	INC	A						; Increment it
	LD	(#CursorCol),A			; Save
	PUSH	AF					; Save register
	CALL	V9938_SetCursorX	; Set cursor on screen	
	POP	AF						; Restore
	CP	#80				
	JP	C,PrintText.RLP			; If up to position 80, done
	XOR	A				
	LD	(#CursorCol),A			; Otherwise cursor is back to position 0
	JP	LineFeed				; And feed the line

;
; Internal Functions area
;
; In this section, functions for the rendering engine use
;

ControlCode:
	OR	A
	RET	Z						; If 0, done
	CP	#8
	JP	Z,BackSpace		
	CP	#10
	JP	Z,LineFeed
	CP	#13
	JP	Z,CarriageReturn
	CP	#27
	JP	Z,EscapeCode			; If an Escape code, let's check it	
	JP	PrintText.RLP



EscapeCode:
	LD	A,(HL)
	INC	HL
	CP	#'['
	JP	Z,Parameters
	CP	#'A'
	JP	Z,VT52_UP
	CP	#'B'
	JP	Z,VT52_DW
	CP	#'C'
	JP	Z,VT52_RI
	CP	#'D'
	JP	Z,VT52_LE
	CP	#'H'
	JP	Z,VT52_HOME
	JP	PrintText.RLP



Parameters:
	LD	(#OrgAddress),HL
	LD	DE,#Parameters.PRM
	LD	(#Parameters.PPT),DE
	XOR	A
	LD	(#Parameters.PCT),A
Parameters.RLP:	
	LD	DE,#Parameters.PST			; PARAMETER STRING
	LD	C,#0
Parameters.SCN:	
	LD	A,(HL)
	INC	HL
	CP	#';'
	JR	Z,Parameters.END
	CP	#'0'
	JR	C,Parameters.END
	CP	#':'
	JR	NC,Parameters.END
	INC	C
	LD	(DE),A
	INC	DE
	JR	Parameters.SCN
Parameters.END:	
	LD	(#Parameters.TRM),A			; SAVE TERMINATING CHAR
	LD	A,C
	OR	A
	;JR	Z,Parameters.OMT			; OMITTED VALUE
	JR	Z,Parameters.SETOMT
	CP	#1
	JR	Z,Parameters.RD1			; READ ONE DIGIT
	CP	#2
	JR	Z,Parameters.RD2			; READ TWO DIGITS
	CP	#3
	JR	Z,Parameters.RD3			; READ THREE DIGITS
Parameters.ERR:	
	XOR	A
	JP	PrintText.RLP
;Parameters.OMT:	
	;If ommited, why 1 parameter?? Should be 0 parameters...
	;INC	A
	;JR	Parameters.SET	
Parameters.RD1:	
	LD	A,(#Parameters.PST)
	SUB	#48
	JR	Parameters.SET
Parameters.RD2:	
	LD	A,(Parameters.PST)
	SUB	#48
	ADD	A,A
	LD	C,A
	ADD	A,A
	ADD	A,A
	ADD	A,C
	LD	C,A
	LD	A,(#Parameters.PST+1)
	SUB	#48
	ADD	A,C
	JR	Parameters.SET
Parameters.RD3:	
	LD	A,(#Parameters.PST)
	SUB	#48
	ADD	A,A
	LD	C,A
	ADD	A,A
	ADD	A,A
	ADD	A,C
	LD	C,A
	LD	A,(#Parameters.PST+1)
	SUB	#48
	ADD	A,C
	ADD	A,A
	LD	C,A
	ADD	A,A
	ADD	A,A
	ADD	A,C
	LD	C,A
	LD	A,(#Parameters.PST+2)
	SUB	#48
	ADD	A,C
Parameters.SET:	
	LD	DE,(#Parameters.PPT)	; PARAMETER POINTER
	LD	(DE),A
	INC	DE
	LD	(#Parameters.PPT),DE
	LD	A,(#Parameters.PCT)		; PARAMETER COUNT
	INC	A
Parameters.SETOMT:		
	LD	B,A	
	LD	(#Parameters.PCT),A
	LD	A,(#Parameters.TRM)		; TERMINATING CHARACTER
	CP	#';'
	JP	Z,Parameters.RLP
	CP	#20
	JP	C,Parameters.ERR

	LD	(#EndAddress),HL

	CP	#'H'
	JP	Z,ANSI_CUP
	CP	#'f'
	JP	Z,ANSI_CUP
	CP	#'R'
	JP	Z,ANSI_CUP
	CP	#'A'
	JP	Z,ANSI_CUU
	CP	#'B'
	JP	Z,ANSI_CUD
	CP	#'C'
	JP	Z,ANSI_CUF
	CP	#'D'
	JP	Z,ANSI_CUB
	CP	#'s'
	JP	Z,ANSI_SCP
	CP	#'u'
	JP	Z,ANSI_RCP
	CP	#'J'
	JP	Z,ANSI_ED
	CP	#'K'
	JP	Z,ANSI_EL
	CP	#'L'
	JP	Z,ANSI_IL
	CP	#'M'
	JP	Z,ANSI_DL
	CP	#'m'
	JP	Z,ANSI_SGR
	CP	#'n'
	JP	Z,ANSI_CGP
	CP	#'P'
	JP	Z,ANSI_DCH

	JP	Parameters.ERR

; OPJ - Add possibility to current cursor position be sent to a callback function
ANSI_CGP:						; ANSI Cursor Get Position
	LD	A,B
	CP	#1				
	JR	NZ,ANSI_CGP.END			; Not only 1 parameter, not 6n, done
	LD	A,(#Parameters.PRM)
	CP	#6						; Is it 6?
	JR	NZ,ANSI_CGP.END			; Not 6, so it is not 6N
	; Ok, ESC[6n, do we have a callback to report cursor position?
	LD	A,(#ANSI_CB)			; Is there a callback programmed?
	OR	A
	JR	Z,ANSI_CGP.END			; Nope, sorry, nothing to do
	; So, lets report the position
	LD	A,(#CursorCol)	
	INC	A
	LD	L,A						; Column goes in L
	LD	A,(#CursorRow)
	INC	A
	LD	H,A						; Row goes in H
ANSI_CGP.CALL_VEC:
	CALL	0					; This address will change when someone wants to receive callbacks
ANSI_CGP.END:	
	LD	HL,(#EndAddress)
	JP	PrintText.RLP


ANSI_CUP:						; ANSI Cursor Position
	LD	A,B
	OR	A
	JR	Z,ANSI_CUP.HOM
	DEC	A
	JR	Z,ANSI_CUP.ROW
	LD	A,(#Parameters.PRM+1)
	DEC	A
	LD	(#CursorCol),A
ANSI_CUP.ROW:	
	LD	A,(#Parameters.PRM+0)
ANSI_CUP.ROW1:	
	DEC	A
	LD	(#CursorRow),A
	JR	ANSI_CUP.RET
ANSI_CUP.HOM:	
	XOR	A
	LD	(#CursorRow),A
	LD	(#CursorCol),A
ANSI_CUP.RET:	
	CALL	V9938_SetCursorX
	CALL	V9938_SetCursorY
	LD	HL,(#EndAddress)
	JP	PrintText.RLP



ANSI_CUU:						; ANSI Cursor Up
	LD	A,B
	LD	B,#1
	OR	A
	JR	Z,ANSI_CUU.SET
ANSI_CUU.GTC:	
	LD	A,(#Parameters.PRM+0)
	LD	B,A
ANSI_CUU.SET:	
	LD	A,(#CursorRow)
	SUB	A,B
	JR	NC,ANSI_CUU.SCP
	XOR	A
ANSI_CUU.SCP:	
	LD	(#CursorRow),A
	CALL	V9938_SetCursorY
	LD	HL,(#EndAddress)
	JP	PrintText.RLP



ANSI_CUD:						; ANSI Cursor Down
	LD	A,B
	LD	B,#1
	OR	A
	JR	Z,ANSI_CUD.SET
ANSI_CUD.GTC:	
	LD	A,(#Parameters.PRM+0)
;OPJ - Fix for 255 so cursor row won't overlap and have a low value when it should be > 24
	CP	#26
	JR	C,ANSI_CUD.SAV
	LD	A,#25
ANSI_CUD.SAV:
	LD	B,A
ANSI_CUD.SET:	
	LD	A,(#CursorRow)
	ADD	A,B
; OPJ changes to allow 25 lines	
	CP	#25
	JR	C,ANSI_CUD.SCP
	LD	A,#24
ANSI_CUD.SCP:	
	LD	(#CursorRow),A
	CALL	V9938_SetCursorY
	LD	HL,(#EndAddress)
	JP	PrintText.RLP



ANSI_CUF:						; ANSI Cursor Forward
	LD	A,B
	LD	B,#1
	OR	A
	JR	Z,ANSI_CUF.SET
ANSI_CUF.GTC:	
	LD	A,(#Parameters.PRM+0)
;OPJ - Fix for 255 so cursor column won't overlap and have a low value when it should be > 24
	CP	#81
	JR	C,ANSI_CUF.SAV
	LD	A,#80
ANSI_CUF.SAV:
	LD	B,A
ANSI_CUF.SET:	
	LD	A,(#CursorCol)
	ADD	A,B
	CP	#80
	JR	C,ANSI_CUF.SCP
	LD	A,#79
ANSI_CUF.SCP:	
	LD	(#CursorCol),A
	CALL	V9938_SetCursorX
	LD	HL,(#EndAddress)
	JP	PrintText.RLP



ANSI_CUB:						; ANSI Cursor Back
	LD	A,B
	LD	B,#1
	OR	A
	JR	Z,ANSI_CUB.SET
ANSI_CUB.GTC:	
	LD	A,(#Parameters.PRM+0)
	LD	B,A
ANSI_CUB.SET:	
	LD	A,(#CursorCol)
	SUB	A,B
	JR	NC,ANSI_CUB.SCP
	XOR	A
ANSI_CUB.SCP:	
	LD	(#CursorCol),A
	CALL	V9938_SetCursorX
	LD	HL,(#EndAddress)
	JP	PrintText.RLP



ANSI_SCP:						; ANSI Save Cursor Position
	LD	A,(#CursorCol)
	LD	(#SavedCol),A
	LD	A,(#CursorRow)
	LD	(#SavedRow),A
	LD	HL,(#EndAddress)
	JP	PrintText.RLP



ANSI_RCP:						; ANSI Restore Cursor Position
	LD	A,(#SavedCol)
	LD	(#CursorCol),A
	LD	A,(#SavedRow)
	LD	(#CursorRow),A
	CALL	V9938_SetCursorX
	CALL	V9938_SetCursorY
	LD	HL,(#EndAddress)
	JP	PrintText.RLP

ANSI_DCH:						; ANSI Delelete Characters
	LD	A,B
	OR	A
	JR	NZ,ANSI_DCH.GP
	; Default is delete one char if no number is given
	INC	A
	JP	V9938_DelChr
ANSI_DCH.GP:	
	LD	A,(#Parameters.PRM+0)	; Load parameter, number of characters to delete
	JP	V9938_DelChr
	

ANSI_ED:						; ANSI Erase in display
	LD	A,B
	OR	A
	JR	Z,ANSI_ED.ED0 			; Default is delete from current position on
	LD	A,(#Parameters.PRM+0)
	CP	#0
	JR	Z,ANSI_ED.ED0
	CP	#1
	JR	Z,ANSI_ED.ED1
	CP	#2
	JR	Z,ANSI_ED.ED2
ANSI_ED.ED0:	
	JP	V9938_ErDis0
ANSI_ED.ED1:	
	JP	V9938_ErDis1
ANSI_ED.ED2:	
	CALL	V9938_ClearScreen
	; Usually should end-up here, but MS-DOS ANSI.SYS legacy place cursor on top left after ED
	; Norm is cursor should be where it was, but, no one follows it, thanks to MS :D
	XOR	A
	LD	(#CursorRow),A
	LD	(#CursorCol),A
	CALL	V9938_SetCursorX
	CALL	V9938_SetCursorY
	LD	HL,(#EndAddress)
	JP	PrintText.RLP



ANSI_EL:						; ANSI Erase in Line
	;DEC	HL
	;DEC	HL
	;LD	A,(HL)
	;CP	#'['
	LD	A,B
	OR	A
	JP	Z,V9938_ErLin0
	LD	A,(#Parameters.PRM+0)
	CP	#1
	JP	Z,V9938_ErLin1
	CP	#2
	JP	Z,V9938_ErLin2
	JP	V9938_ErLin0



ANSI_IL:
	; TODO: Missing Handling of inserting lines from current
	LD	HL,(#EndAddress)
	JP	PrintText.RLP

ANSI_DL:
	; TODO: Missing Handling of deleting lines from current
	LD	HL,(#EndAddress)
	JP	PrintText.RLP



ANSI_SGR:						; ANSI Set Graphics Rendition
	LD	A,B
	OR	A
	;JR	Z,ANSI_SGR.RET
	; OPJ: Zero parameters -> Reset attributes
	JR	Z,ANSI_SGR.RES			; RESET ATTRIBUTES
	LD	DE,#Parameters.PRM
ANSI_SGR.RLP:	
	PUSH	BC
	LD	A,(DE)
	INC	DE
	OR	A
	JR	Z,ANSI_SGR.RES			; RESET ATTRIBUTES
	CP	#1
	JR	Z,ANSI_SGR.BLD			; SET FONT TO BOLD
	CP	#30
	JR	C,ANSI_SGR.UNK			; UNKNOWN / UNSUPPORTED
	CP	#38
	JR	C,ANSI_SGR.SFC			; SET FOREGROUND COLOR
	CP	#40
	JR	C,ANSI_SGR.UNK			; UNKNOWN / UNSUPPORTED
	CP	#48
	JR	C,ANSI_SGR.SBC			; SET BACKGROUND COLOR
ANSI_SGR.UNK:	
	POP	BC
	DJNZ	ANSI_SGR.RLP
ANSI_SGR.RET:	
	LD	HL,(#EndAddress)
	JP	PrintText.RLP
ANSI_SGR.RES:	
	XOR	A						; RESET ATTRIBUTES
	LD	(#HiLighted),A
	LD	(#BackColor),A
	LD	A,#0x07
	LD	(#ForeColor),A
	JR	ANSI_SGR.CLR
ANSI_SGR.BLD:	
	LD	A,#0x01
	LD	(#HiLighted),A
	JR	ANSI_SGR.CLR
ANSI_SGR.SFC:	
	SUB	#30
	LD	(#ForeColor),A
	JR	ANSI_SGR.CLR
ANSI_SGR.SBC:	
	SUB	#40
	LD	(#BackColor),A
	JR	ANSI_SGR.CLR
ANSI_SGR.CLR:	
	CALL	V9938_SetColors
	JR	ANSI_SGR.UNK


VT52_UP:
	LD	A,(#CursorRow)
	OR	A
	JP	Z,PrintText.RLP
	DEC	A
	LD	(#CursorRow),A
	CALL	V9938_SetCursorY
	JP	PrintText.RLP



VT52_DW:
	LD	A,(#CursorRow)
	CP	#24
	JP	NC,PrintText.RLP
	INC	A
	LD	(#CursorRow),A
	CALL	V9938_SetCursorY
	JP	PrintText.RLP



VT52_LE:
	LD	A,(#CursorCol)
	OR	A
	JP	Z,PrintText.RLP
	DEC	A
	LD	(#CursorCol),A
	CALL	V9938_SetCursorX
	JP	PrintText.RLP



VT52_RI:
	LD	A,(#CursorCol)
	CP	#79
	JP	NC,#PrintText.RLP
	INC	A
	LD	(#CursorCol),A
	CALL	V9938_SetCursorX
	JP	PrintText.RLP



VT52_HOME:
	XOR	A
	LD	(#CursorCol),A
	LD	(#CursorRow),A
	CALL	V9938_SetCursorX
	CALL	V9938_SetCursorY
	JP	PrintText.RLP



BackSpace:
	LD	A,(#CursorCol)
	OR	A
	JP	Z,PrintText.RLP
	DEC	A
	LD	(#CursorCol),A
	CALL	V9938_SetCursorX
	JP	PrintText.RLP



HorizontalTab:
	LD	A,(#CursorCol)
	ADD	#0x08
	AND	#0b11111000
	LD	(#CursorCol),A
	CP	#80
	JP	C,HorizontalTab.RET
	SUB	#80
	LD	(#CursorCol),A
	JP	LineFeed
HorizontalTab.RET:	
	CALL	V9938_SetCursorX
	CALL	V9938_SetCursorY
	JP	PrintText.RLP



LineFeed:
	LD	A,(#CursorRow)
	INC	A
	CP	#25
	JR	C,LineFeed.NNL
	CALL	V9938_LineFeed
	LD	A,#24
LineFeed.NNL:	
	LD	(#CursorRow),A
	CALL	V9938_SetCursorX
	CALL	V9938_SetCursorY
	JP	PrintText.RLP



CarriageReturn:
	XOR	A
	LD	(#CursorCol),A
	CALL	V9938_SetCursorX
	JP	PrintText.RLP


_BIOS_C:				; BIOS_C: [IX]
	LD	IY,(#0xFCC0)
	JP	0x001C

;
;	V9938 Related Code
;
;	This is where all V9938 (MSX2/2+) specific routines and defines are
;

VDP_08	.equ	#0xFFE7
VDP_09	.equ	#0xFFE8
VDP_23	.equ	#0xFFF6
VDP_01	.equ	#0xF3E0
VDP_06	.equ	#0xF3E5
VDP_05	.equ	#0xF3E4
VDP_11	.equ	#0xFFEA
VDP_14	.equ	#0xFFED

; SUB-ROM entries
;
iniPlt	.equ	#0x0141
rstPlt	.equ	#0x0145

; CALSUB
;
; In: IX = address of routine in MSX2 SUBROM
;     AF, HL, DE, BC = parameters for the routine
;
; Out: AF, HL, DE, BC = depending on the routine
;
; Changes: IX, IY, AF', BC', DE', HL'
;
; Call MSX2 subrom from MSXDOS. Should work with all versions of MSXDOS.
;
; Notice: NMI hook will be changed. This should pose no problem as NMI is
; not supported on the MSX at all.
;
CALSLT	.equ	#0x001C
NMI		.equ	#0x0066
EXTROM	.equ	#0x015F
EXPTBL	.equ	#0xFCC1
H_NMI	.equ	#0xFDD6
;
CALSUB:  
	EXX
	EX     AF,AF'       ; store all registers
	LD     HL,#EXTROM
	PUSH   HL
	LD     HL,#0xC300
	PUSH   HL           ; push NOP ; JP EXTROM
	PUSH   IX
	LD     HL,#0x21DD
	PUSH   HL           ; push LD IX,<entry>
	LD     HL,#0x3333
	PUSH   HL           ; push INC SP; INC SP
	LD     HL,#0
	ADD    HL,SP        ; HL = offset of routine
	LD     A,#0xC3
	LD     (#H_NMI),A
	LD     (#H_NMI+1),HL ; JP <routine> in NMI hook
	EX     AF,AF'
	EXX                 ; restore all registers
	LD     IX,#NMI
	LD     IY,(#EXPTBL-1)
	CALL   CALSLT       ; call NMI-hook via NMI entry in ROMBIOS
					 ; NMI-hook will call SUBROM
	EXX
	EX     AF,AF'       ; store all returned registers
	LD     HL,#10
	ADD    HL,SP
	LD     SP,HL        ; remove routine from stack
	EX     AF,AF'
	EXX                 ; restore all returned registers
	RET


V9938_Init:

	LD	A,#0x07
	LD	IX,#0x005F
	CALL	_BIOS_C			; Interslot call to set screen 7	
	
	; Now let's set a lot of registers :)
	LD	A,#0x00
	LD	(#VDP_23),A			; R#23, first line to draw is 0
	
	DI
	LD	A,#0xF0				; Text1 and Text2 color 15, Border and Background color 0
	OUT	(#0x99),A
	LD	A,#0x80+7
	OUT	(#0x99),A			; Write to register 7
	
	LD	A,(#VDP_08)			; Get a copy of register 8
	OR	#0b00100010			; Set bit so color 0 is 0 in palette and disable sprites	
	LD	(#VDP_08),A			; Save our value
	OUT	(#0x99),A			; Send value to VDP
	LD	A,#0x80+8				
	OUT	(#0x99),A			; Write to register 8	
	
	LD	A,(#VDP_09)			; Get a copy of register 9
	OR	#0b10000000			; 212 Lines by seting 8th bit
	LD	(#VDP_09),A			; Save our new value
	OUT	(#0x99),A			; Send value to VDP	
	LD	A,#0x80+9
	OUT	(#0x99),A			; Write to register 9	
	
	LD	A,#0x00				; Palette register pointer set to 0
	OUT	(#0x99),A			; Send value to VDP
	LD	A,#0x80+16			; 
	OUT	(#0x99),A			; Write to register 16, new palette pointer
	EI						; Ok to have interrupts now
	LD	HL,#ANSI_PAL		; Address of our palette
	LD	BC,#0x209A			; 32 bytes to move to port 0x9a which will auto-increment palette registers
	OTIR					; Send it
	RET						; Done!

V9938_Finish:
	DI
	LD	A,#0x00
	OUT	(#0x99),A
	LD	A,#0x80+23
	OUT	(#0x99),A			; Register 23 goes to 0 to reset vertical offset
	
	LD	IX,#0xD2
	LD	IY,(#0xFCC0)		; Call TOTEXT bios function
	CALL CALSLT
	EI
	
	LD	IX,#iniPlt
	CALL	CALSUB	
	LD	IX,#rstPlt			; Restore the saved palette
	CALL CALSUB
	EI
	
	RET						; Done!

;OPJ - Sprite Cursor initialization		
V9938_InitCursor:
	DI
	; First Set Pattern Table Address
	LD	A,#0b00111111		; sprite pattern table = #1F800-#1FFFF
	LD	(#VDP_06),A			; Save our value
	OUT	(#0x99),A			; Send value
	LD	A,#0x80+6	
	OUT	(#0x99),A			; Write in register
	
	; Now Set Sprite Attribute Table Address
	LD	A,#0b11101111		; sprite attribute table = #1F600 / So Color Table will be #1F400 (14 - 10 and 3 1s)
	LD	(#VDP_05),A			; Save our value
	OUT	(#0x99),A			; Send value
	LD	A,#0x80+5	
	OUT	(#0x99),A			; Write in register
	LD	A,#0b00000011		; A16 - 1 And A15 - 1
	LD	(#VDP_11),A			; Save our value
	OUT	(#0x99),A			; Send value
	LD	A,#0x80+11	
	OUT	(#0x99),A			; Write in register
	
	;SET VDP TO WRITE @ Color Table starting at Sprite 0 (#1F400)
	LD	A,#0b00000111		; A16, A15 and A14 set to 1
	LD	(#VDP_14),A			; Save our value	
	OUT	(#0x99),A			; Send value	
	LD	A,#0x80+14
	OUT	(#0x99),A			; Write in register
	LD	A,#0b00000000		; Now A7 to A0, all 0's
	OUT	(#0x99),A			; Low Address
	LD	A,#0b01110100		; Write (bit 6), A13/A12 to 1(1F) / A11 to 0 and A10 to 1 and A9-A8 to 0 (4)
	OUT	(#0x99),A			; High Address	
	
	;Colors for 2 sprites is 32 bytes long
	LD	HL,#SPRITE_COLORS
	LD	BC,#0x2098
V9938_InitCursor.COLRLOOP:	
	OUTI
	NOP
	NOP
	JR	NZ,V9938_InitCursor.COLRLOOP		
	
	;SET VDP TO WRITE @ Pattern Table starting at Sprite 0 (#1F800)
	LD	A,#0b00000111		; A16/15/14 set to 1
	LD	(#VDP_14),A			; Save our value
	OUT	(#0x99),A			; Send value	
	LD	A,#0x80+14
	OUT	(#0x99),A			; Write in register
	LD	A,#0b00000000		; Now A7 to A0, all 0's
	OUT	(#0x99),A			; Low Address
	LD	A,#0b01111000		; Write (bit 6),  A12 1 
	OUT	(#0x99),A			; High Address	
	
	;Patterns for 2 sprites is 16 bytes long
	LD	HL,#PATTERN_CURSOR
	LD	BC,#0x1098
V9938_InitCursor.PATRNLOOP:	
	OUTI
	NOP
	NOP
	JR	NZ,V9938_InitCursor.PATRNLOOP
	
	;SET VDP TO WRITE @ Attribute Table starting at Sprite 0 (#1F600)
	LD	A,#0b00000111		; A16, A15 and A14 set to 1
	LD	(#VDP_14),A			; Save our value
	OUT	(#0x99),A			; Send value	
	LD	A,#0x80+14
	OUT	(#0x99),A			; Write in register
	LD	A,#0b00000000		; Now A7 to A0, all 0's
	OUT	(#0x99),A			; Low Address
	LD	A,#0b01110110		; Write (bit 6), A13/A12 to 1(1F) / A11 to 0 and A10/A9 to 1 and A8 to 0 (6)
	OUT	(#0x99),A			; High Address	
	
	;Attributes for 2 sprites is 8 bytes long
	LD	HL,#SPRITE_TABLE
	LD	BC,#0x0898
V9938_InitCursor.ATTRLOOP:	
	OUTI
	NOP
	NOP
	JR	NZ,V9938_InitCursor.ATTRLOOP
		
	; Done with setting
	DI
	LD	A,(#VDP_08)			; Get a copy of register 8
	AND #0b11111101			; Enable Sprites (cursor)
	LD	(#VDP_08),A			; Save our value
	OUT	(#0x99),A			; Send value to VDP
	LD	A,#0x80+8				
	OUT	(#0x99),A			; Write to register 8
	EI
	RET

V9938_CursorColor:
	;SET VDP TO WRITE @ Color Table starting at Sprite 0 Line 6 (#1F405)
	LD	A,#0b00000111		; A16, A15 and A14 set to 1
	DI
	LD	(#VDP_14),A			; Save our value	
	OUT	(#0x99),A			; Send value	
	LD	A,#0x80+14
	OUT	(#0x99),A			; Write in register
	LD	A,#0b00000101		; Now A7 to A0
	OUT	(#0x99),A			; Low Address
	LD	A,#0b01110100		; Write (bit 6), A13/A12 to 1(1F) / A11 to 0 and A10 to 1 and A9-A8 to 0 (4)
	OUT	(#0x99),A			; High Address	

	LD	A,(#HiLighted)
	OR	A
	LD	A,(#ForeColor)
	JR	Z,V9938_CursorColor.NHA
	ADD	#0x08
V9938_CursorColor.NHA:	
	OR	#0x20				; Color attribute
	LD	B,#2
V9938_CursorColor.CCLRLOOP:	
	;Update 1st line
	OUT	(#0x98),A
	NOP
	NOP
	DJNZ	V9938_CursorColor.CCLRLOOP
	EI
	RET

V9938_MoveCursorY:		
	;SET VDP TO WRITE @ #0x1F600 - Attribute Table
	LD	A,#0b00000111		; A16, A15 and A14 set to 1
	LD	(#VDP_14),A			; Save our value
	DI
	OUT	(#0x99),A			; Send value	
	LD	A,#0x80+14
	OUT	(#0x99),A			; Write in register
	LD	A,#0b00000000		; Now A7 to A0, all 0's
	OUT	(#0x99),A			; Low Address
	LD	A,#0b01110110		; Write (bit 6), A13/A12 to 1(1F) / A11 to 0 and A10/A9 to 1 and A8 to 0 (6)
	OUT	(#0x99),A			; High Address		
	; Y Position
	LD	A,(#HMMC_CMD.DYL)
	LD	B,A					; Copy IYL to B
	LD	A,(#VDP_23)			; Get current vertical offset
	ADD	A,B					; Add our IYL to it
	OUT	(#0x98),A			; Set Y
	EI
	RET

V9938_MoveCursorX:		
	;SET VDP TO WRITE @ #0x1F601 - Attribute Table
	LD	A,#0b00000111		; A16, A15 and A14 set to 1
	LD	(#VDP_14),A			; Save our value
	DI
	OUT	(#0x99),A			; Send value	
	LD	A,#0x80+14
	OUT	(#0x99),A			; Write in register
	LD	A,#0b00000001		; Now A7 to A0, all 0's
	OUT	(#0x99),A			; Low Address
	LD	A,#0b01110110		; Write (bit 6), A13/A12 to 1(1F) / A11 to 0 and A10/A9 to 1 and A8 to 0 (6)
	OUT	(#0x99),A			; High Address		
	; X Position	
	LD	A,(#HMMC_CMD.DXL)
	ADD	A,#8
	OUT	(#0x98),A			; Set X
	EI
	RET	
;END OPJ Changes Sprite	

V9938_PrintChar:
	CP	#0x20
	JR	Z,V9938_PrintChar.SPC
	CP	#0xDB
	JR	Z,V9938_PrintChar.FIL
	LD	DE,#FontData
	LD	L,A
	LD	H,#0
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,DE
	LD	DE,#ColorTable
	LD	A,(HL)
	AND	#0b11000000
	RLC	A
	RLC	A
	ADD	A,#ColorTable; AND 255
	LD	E,A
	LD	A,(DE)
	LD	(#HMMC_CMD.CLR),A
	PUSH	HL
	CALL	DO_HMMC
	POP	HL
	LD	BC,#0x089B
	JR	V9938_PrintChar.BP1
V9938_PrintChar.BP0:	LD	A,(HL)
	AND	#0b11000000
	RLC	A
	RLC	A
	ADD	A,#ColorTable; AND 255
	LD	E,A
	LD	A,(DE)
	OUT	(C),A
V9938_PrintChar.BP1:	LD	A,(HL)
	AND	#0b00110000
	RRCA
	RRCA
	RRCA
	RRCA
	ADD	A,#ColorTable; AND 255
	LD	E,A
	LD	A,(DE)
	OUT	(C),A
V9938_PrintChar.BP2:	LD	A,(HL)
	AND	#0b00001100
	RRCA
	RRCA
	ADD	A,#ColorTable; AND 255
	LD	E,A
	LD	A,(DE)
	OUT	(C),A
V9938_PrintChar.RLP:	INC	HL
	DJNZ	V9938_PrintChar.BP0
	RET
V9938_PrintChar.SPC:	LD	A,(#ColorTable+0)
	LD	(HMMC_CMD.CLR),A
	CALL	DO_HMMC
	LD	A,(#ColorTable+0)
V9938_PrintChar.OUT:	LD	BC,#0x179B
V9938_PrintChar.SPL:	OUT	(C),A
	DJNZ	V9938_PrintChar.SPL
	RET
V9938_PrintChar.FIL:	LD	A,(#ColorTable+3)
	LD	(#HMMC_CMD.CLR),A
	CALL	DO_HMMC
	LD	A,(#ColorTable+3)
	JR	V9938_PrintChar.OUT



V9938_LineFeed:
	PUSH	HL
	LD	A,#25
	CALL	V9938_ClearLine
	; OPJ - To avoid previous lines to show in the bottom when rolling multiple lines
	CALL	V9938_ClearTop
	POP	HL
	LD	A,(#VDP_23)
	ADD	#0x08
	LD	(#VDP_23),A
	DI
	OUT	(#0x99),A
	LD	A,#0x80+23
	OUT	(#0x99),A
	EI
	RET



V9938_SetCursorX:
	LD	A,(#CursorCol)
	LD	B,A
	ADD	A,A
	ADD	A,B
	LD	(#HMMC_CMD.DXL),A
	;OPJ - Update Cursor Position
	JP	V9938_MoveCursorX
	;RET



V9938_SetCursorY:
	LD	A,(#CursorRow)
	ADD	A,A
	ADD	A,A
	ADD	A,A
	LD	(#HMMC_CMD.DYL),A
	;OPJ - Update Cursor Position
	JP	V9938_MoveCursorY
	;RET



V9938_ClearLine:
	ADD	A,A
	ADD	A,A
	ADD	A,A
	LD	(#HMMV_CMD.DYL),A ; Number of lines * 8 = position of the last line
	LD	A,#0x08
	LD	(#HMMV_CMD.NYL),A ; Will paint a rectangle with 8 pixels on the Y axys
	XOR	A
	LD	(#HMMV_CMD.NYH),A
	LD	(#HMMV_CMD.DXL),A ; 
	LD	A,#0xE0
	LD	(#HMMV_CMD.NXL),A
	LD	A,#0x01
	LD	(#HMMV_CMD.NXH),A ; The rectangle is 480 pixels on the X axis
	LD	A,(#BackColor)
	ADD	A,A
	ADD	A,A
	ADD	A,A
	ADD	A,A
	LD	B,A
	LD	A,(#BackColor)
	OR	B				; Adjust color in the right format
	LD	(#HMMV_CMD.CLR),A; Color to paint the rectangle
	JP	DO_HMMV

; OPJ - To avoid previous lines to show in the bottom when rolling multiple lines
V9938_ClearTop:
	XOR	A
	LD	(#HMMV_CMD.DYL),A ; position of the first line
	LD	A,#0x08
	LD	(#HMMV_CMD.NYL),A ; Will paint a rectangle with 8 pixels on the Y axys
	XOR	A
	LD	(#HMMV_CMD.NYH),A
	LD	(#HMMV_CMD.DXL),A ; 
	LD	A,#0xE0
	LD	(#HMMV_CMD.NXL),A
	LD	A,#0x01
	LD	(#HMMV_CMD.NXH),A ; The rectangle is 480 pixels on the X axis
	LD	A,(#BackColor)
	ADD	A,A
	ADD	A,A
	ADD	A,A
	ADD	A,A
	LD	B,A
	LD	A,(#BackColor)
	OR	B				; Adjust color in the right format
	LD	(#HMMV_CMD.CLR),A; Color to paint the rectangle
	JP	DO_HMMV


V9938_ClearScreen:
	CALL	V9938_WaitCmd	; Make sure VDP is not processing any command
	DI
	;OPJ - Set border color same as back color
	LD	A,(#BackColor)		; Text1 and Text2 color 15, Border and Background color 0
	OUT	(#0x99),A
	LD	A,#0x80+7
	OUT	(#0x99),A				; Write to register 7
	;OPJ - End
	LD	A,#0x24				;
	OUT	(#0x99),A
	LD	A,#0x91
	OUT	(#0x99),A				; Indirect access to registers, starting at #36
	EI
	LD	C,#0x9B				;Now indirect writes starting at register 36
	XOR	A
	OUT	(C),A	; DXL = 0
	NOP
	OUT	(C),A	; DXH = 0
	NOP
	OUT	(C),A	; DYL = 0
	NOP
	OUT	(C),A	; DYH = 0
	NOP
	OUT	(C),A	; NXL  = 0
	LD	A,#0x02
	OUT	(C),A	; NXH = 2 (512 dots)
	XOR	A
	OUT	(C),A	; NYL = 0
	INC	A
	OUT	(C),A	; NYH = 1 (256 dots)
	LD	A,(#BackColor)
	ADD	A,A
	ADD	A,A
	ADD	A,A
	ADD	A,A
	LD	B,A
	LD	A,(#BackColor)
	OR	B
	OUT	(C),A	; CLR
	LD	A,#0x00
	OUT	(C),A	; ARG
	LD	A,#0xC0
	OUT	(C),A	; CMD	
	RET

	; Observing Windows 10 terminal behavior as well as XTERM, Del Char only deletes characters in the same line
	; Lines below are left untouched even if # of chars to delete surpass the # of chars in the line, and it does
	; not shift lines below up. 
V9938_DelChr:
	LD	C,A					; Number of characters to delete in C
	LD	A,(#CursorCol)		;
	LD	B,A					; Cursor column in B
	ADD	A,C					; Lets Check if cursor pos + deleted characters equals or exceed a line limit
	CP	#79					; So, if 78 (79 columns) or less, will carry
	JP	NC,V9938_ErLin0		; If no carry, no need to move blocks, we can just use a line deletion that will be way faster
	; If here cursor pos + deleted characters less than a line, so we need to do the following:
	; - Calculate the size of the block to move (End of screen - (Cursor Position + Deleted Chars))
	; - Move the block
	; - Erase # of Deleted Chars after the end of the block
	LD	A,#80
	SUB	A,B					; Ok, how many characters do we have including the one in cursor?
	SUB	A,C					; And this is how many characters we need to copy to cursor position
	INC A					;
	PUSH	AF				; Save this, we will use it later to delete characters by fake positioning cursor @ cursor pos + moved characters +1 and deleting from there to the end of line :)
	LD	B,A					; B contains character width of block being moved
	ADD	A,A
	ADD	A,B					; Multiply it by 3, number of "double pixels" (6 pixel width, 3 double pixels width)
	ADD	A,A					; And now double it to adjust lsb not considered
	LD	(#HMMM_CMD.NXL),A	; Store as NX lower byte
	LD	A,#0x00				; Probably will be 0 NX higher byte
	JR	NC,V9938_DelChr.NXH	; But if carry, means it is 1
	INC	A					; If carry, NXh is 1
V9938_DelChr.NXH:	LD	(#HMMM_CMD.NXH),A	; Store it
	LD	A,#0x08
	LD	(#HMMM_CMD.NYL),A
	; No need to change NYH, always 0
	LD	A,(#CursorCol)
	LD	B,A
	ADD	A,A
	ADD	A,B					; Just adjust to count of "double pixels", HMMM function will handle DXH and shifting it
	LD	(#HMMM_CMD.DXL),A	; Destination is current cursor position
	LD	D,A					; Save A in D
	LD	A,C					; Now source is what is in D + 3 times what is in C
	LD	B,A
	ADD	A,A
	ADD	A,B					; A contains 3xdeleted characters
	ADD A,D					; + cursor position, this is the position of source X :D
	LD	(#HMMM_CMD.SXL),A	; Source is current cursor position + deleted characters
	LD	A,(#CursorRow)		; Current cursor line
	ADD	A,A
	ADD	A,A
	ADD	A,A					; Multiply it by 8, it is the first line of that character line (8 pixels high character)
	LD	(#HMMM_CMD.DYL),A	; This is the Y destination
	LD	(#HMMM_CMD.SYL),A	; As well as the Y source
	CALL	DO_HMMM			; All set, let's move
	POP	BC					; What we need to Add to Cursor is restored in B
	LD	A,(#CursorCol)		; Current Cursor Column
	ADD	A,B					; Our fake cursor position
	JP	V9938_ErLin0.1		; Erase Line, but using what is in A, our fake cursor position, and return to processing after done

	
	
V9938_DelChr.SL:	LD	HL,(#EndAddress)
	JP	PrintText.RLP	

V9938_ErDis0:
	LD	A,(#CursorCol)
	LD	B,A
	ADD	A,A
	ADD	A,B
	LD	(#HMMV_CMD.DXL),A	; DX = Number of column * 3 (this mode has doubled pixels in X axis)
	LD	B,A
	LD	A,#240				; We draw up to 240 double-pixels (6 pixels wide characters * 80 columns)
	SUB	A,B					; Except the  pixels data up to the cursor position
	ADD	A,A					; And now double  it
	LD	(#HMMV_CMD.NXL),A	; Store as NX lower byte
	LD	A,#0x00				; Probably will be 0 NX higher byte
	JR	NC,V9938_ErDis0.NXH	; But if carry, means it is 1
	INC	A					; If carry, NXh is 1
V9938_ErDis0.NXH:	LD	(#HMMV_CMD.NXH),A	; Store it
	LD	A,(#CursorRow)		; Now get the row / line
	ADD	A,A					; 8 pixels height each character, multiply it per 8
	ADD	A,A
	ADD	A,A
	LD	(#HMMV_CMD.DYL),A	; This is the Y axys start
	LD	A,#0x08				
	LD	(#HMMV_CMD.NYL),A	; To clear a single line it is 8 pixels height number of dots height
	XOR	A
	LD	(#HMMV_CMD.DYH),A	; DYH and NYH 0
	LD	(#HMMV_CMD.NYH),A
	CALL	DO_HMMV			; Aaaand.... Clear!
	; Now, do we need to clear below cursor?
	LD	A,(#CursorRow)		; Let's see how many pixels we need to fill
	LD	B,A					; Now get the row / line in B
	LD	A,#24				; Up to 25 lines, 0 is first, 24 is the 25th line
	SUB	A,B					; Let's check how many extra lines need to be cleared
	JR	Z,V9938_ErDis0.SL	; If last line, done
	; Not last, so multiply it per 8
	ADD	A,A
	ADD	A,A
	ADD	A,A
	LD	(#HMMV_CMD.NYL),A	; To clear remaining lines it is 8 pixels height multiplied by number of lines
	XOR	A				
	LD	(#HMMV_CMD.DYH),A	; DYH and NYH and DXL 0
	LD	(#HMMV_CMD.NYH),A	;
	LD	(#HMMV_CMD.DXL),A	; 
	LD	A,#0xE0				; We draw 240 double-pixels (6 pixels wide characters * 80 columns), 480 pixels, 0x01E0
	LD	(#HMMV_CMD.NXL),A	; Store as NX lower byte
	LD	A,#1				;
	LD	(#HMMV_CMD.NXH),A	; Store NX higher byte
	LD	A,(#CursorRow)		; Now get the row / line
	INC	A					; Next line
	ADD	A,A					; 8 pixels height each character, multiply it per 8
	ADD	A,A					;
	ADD	A,A					;	
	LD	(#HMMV_CMD.DYL),A	; This is the Y axys start
	CALL	DO_HMMV			; Aaaand.... Clear!	
V9938_ErDis0.SL:	LD	HL,(#EndAddress)
	JP	PrintText.RLP

V9938_ErDis1:
	XOR	A
	LD	(#HMMV_CMD.DXL),A	; DX = Beginning of line, 0
	LD	(#HMMV_CMD.DXH),A	; DX = Beginning of line, 0
	LD	A,(#CursorCol)
	LD	B,A
	ADD	A,A
	ADD	A,B					; Column * 6 = X coordinate of current cursor position
	ADD	A,A					; And now double  it
	LD	(#HMMV_CMD.NXL),A	; Store as NX lower byte
	LD	A,#0x00				; Probably will be 0 NX higher byte
	JR	NC,V9938_ErDis1.NXH	; But if carry, means it is 1
	INC	A					; If carry, NXh is 1
V9938_ErDis1.NXH:	LD	(#HMMV_CMD.NXH),A	; Store it
	LD	A,(#CursorRow)		; Now get the row / line
	ADD	A,A					; 8 pixels height each character, multiply it per 8
	ADD	A,A
	ADD	A,A
	LD	(#HMMV_CMD.DYL),A	; This is the Y axys start
	LD	A,#0x08				
	LD	(#HMMV_CMD.NYL),A	; To clear a single line it is 8 pixels height number of dots height
	XOR	A
	LD	(#HMMV_CMD.DYH),A	; DYH and NYH 0
	LD	(#HMMV_CMD.NYH),A
	CALL	DO_HMMV			; Aaaand.... Clear!
	; Now, do we need to clear above cursor?
	LD	A,(#CursorRow)		; Let's see how many pixels we need to fill
	OR	A					; First row/line?
	JR	Z,V9938_ErDis1.SL	; If first line, done
	; Not first, so multiply it per 8
	LD	A,A					;
	LD	A,A					;	
	LD	(#HMMV_CMD.NYL),A	; To clear remaining lines it is 8 pixels height multiplied by number of lines - 1 (which is cursor row)
	XOR	A				
	LD	(#HMMV_CMD.DYH),A	; DYH, DYL, DXL ,DXH  and and NYH 0
	LD	(#HMMV_CMD.DYL),A	; 
	LD	(#HMMV_CMD.NYH),A	;
	LD	(#HMMV_CMD.DXL),A	; 
	LD	(#HMMV_CMD.DXH),A	; 
	LD	A,#0xE0				; We draw 240 double-pixels (6 pixels wide characters * 80 columns), 480 pixels, 0x01E0
	LD	(#HMMV_CMD.NXL),A	; Store as NX lower byte
	LD	A,#1				;
	LD	(#HMMV_CMD.NXH),A	; Store NX higher byte
	CALL	DO_HMMV			; Aaaand.... Clear!	
V9938_ErDis1.SL:	LD	HL,(#EndAddress)
	JP	PrintText.RLP

V9938_ErLin0:
	LD	A,(#CursorCol)
V9938_ErLin0.1:
	LD	B,A
	ADD	A,A
	ADD	A,B
	LD	(#HMMV_CMD.DXL),A
	LD	B,A
	LD	A,#240
	SUB	A,B
	ADD	A,A
	LD	(#HMMV_CMD.NXL),A
	LD	A,#0x00
	JR	NC,V9938_ErLin0.NXH
	INC	A
V9938_ErLin0.NXH:	LD	(#HMMV_CMD.NXH),A
	LD	A,(#CursorRow)
	ADD	A,A
	ADD	A,A
	ADD	A,A
	LD	(#HMMV_CMD.DYL),A
	LD	A,#0x08
	LD	(#HMMV_CMD.NYL),A
	XOR	A
	LD	(#HMMV_CMD.DYH),A
	LD	(#HMMV_CMD.NYH),A
	CALL	DO_HMMV
	LD	HL,(#EndAddress)
	JP	PrintText.RLP



V9938_ErLin1:
	XOR	A
	LD	(#HMMV_CMD.DXL),A
	LD	(#HMMV_CMD.DXH),A
	LD	A,(#CursorCol)
	LD	B,A
	ADD	A,A
	ADD	A,B
	LD	C,#0
	ADD	A,A
	JR	NC,V9938_ErLin1.CNT
	INC	C
V9938_ErLin1.CNT:	LD	(#HMMV_CMD.NXL),A
	LD	A,C
	JP	V9938_ErLin0.NXH



V9938_ErLin2:
	LD	A,(#CursorRow)	; Clear Entire Line
	CALL	V9938_ClearLine
	XOR	A
	LD	(#CursorCol),A
	CALL	V9938_SetCursorX
	LD	HL,(#EndAddress)
	JP	PrintText.RLP



V9938_SetColors:
	LD	A,(#HiLighted)
	OR	A
	LD	A,(#ForeColor)
	JR	Z,V9938_SetColors.NHA
	ADD	#0x08
V9938_SetColors.NHA:	LD	B,A
	ADD	A,A
	ADD	A,A
	ADD	A,A
	ADD	A,A
	OR	B
	LD	(#FontColor),A
	LD	A,(#BackColor)
	ADD	A,A
	ADD	A,A
	ADD	A,A
	ADD	A,A
	LD	B,A
	LD	A,(#BackColor)
	OR	B
	LD	(#ColorTable+00),A
	LD	A,(#FontColor)
	AND	#0x0F
	OR	B
	LD	(#ColorTable+01),A
	LD	A,(#FontColor)
	AND	#0xF0
	LD	B,A
	LD	A,(#BackColor)
	OR	B
	LD	(#ColorTable+02),A
	LD	A,(#FontColor)
	LD	(#ColorTable+03),A
	;OPJ - Sprite Cursor added
	JP	V9938_CursorColor
	;RET



V9938_WaitCmd:
	LD	A,#0x02
	DI
	OUT	(#0x99),A
	LD	A,#0x80+15
	OUT	(#0x99),A
	IN	A,(#0x99)
	RRA
	LD	A,#0x00
	OUT	(#0x99),A
	LD	A,#0x80+15
	EI
	OUT	(#0x99),A
	RET	NC
	JP	V9938_WaitCmd


DO_HMMC:
	CALL	V9938_WaitCmd	; Wait if any command is pending
	DI
	LD	A,#0x24				; Register 36 as value for...
	OUT	(#0x99),A
	LD	A,#0x91				; Register #17 (indirect register access auto increment)
	OUT	(#0x99),A
	LD	HL,#HMMC_CMD		; The HMMC buffer
	LD	C,#0x9B				; And port for indirect access
	LD	A,(HL)				; LD DXL in A
	INC	HL
	INC	HL					; HL pointing to DYL
	ADD	#0x08				; Add 8 to DXL (A) - Border of 16 pixels
	ADD	A,A					; Multiply by 2
	OUT	(C),A				; And send DXL to #36
	LD	A,#0x00				; DXH could be 0
	JR	NC,DO_HMMC.DXH		; If no carry, it is 0
	INC	A					; Otherwise it is 1
DO_HMMC.DXH:	OUT	(C),A	; And send DXH to #37
	LD	A,(HL)				; Load DYL in A
	INC	HL					
	INC	HL					; HL pointing @ NXL
	LD	B,A					; Copy DYL to B
	LD	A,(#VDP_23)			; Get current vertical offset
	ADD	A,B					; Add our DYL to it
	OUT	(C),A				; Send it to #38
	XOR	A					; DYH always 0
	OUT	(C),A				; Send it
	OUTI					; And now send the rest of buffer
	OUTI
	OUTI
	OUTI
	OUTI
	OUTI
	OUTI
	LD	A,#0xAC				
	OUT	(#0x99),A
	LD	A,#0x91				
	OUT	(#0x99),A
	EI
	RET



DO_HMMV:
	CALL	V9938_WaitCmd
	DI
	LD	A,#0x24
	OUT	(#0x99),A
	LD	A,#0x91
	OUT	(#0x99),A
	LD	HL,#HMMV_CMD
	LD	C,#0x9B
	LD	A,(HL)
	INC	HL
	INC	HL
	ADD	#0x08
	ADD	A,A
	OUT	(C),A
	LD	A,#0x00
	JR	NC,DO_HMMV.DXH
	INC	A
DO_HMMV.DXH:	OUT	(C),A
	LD	A,(HL)
	INC	HL
	INC	HL
	LD	B,A
	LD	A,(#VDP_23)
	ADD	A,B
	OUT	(C),A
	XOR	A
	OUT	(C),A
	OUTI
	OUTI
	OUTI
	OUTI
	OUTI
	OUTI
	OUTI
	EI
	RET
	

DO_HMMM:
	CALL	V9938_WaitCmd	; Wait if any command is pending
	DI
	LD	A,#0x20				; Register 32 as value for...
	OUT	(#0x99),A
	LD	A,#0x91				; Register #17 (indirect register access auto increment)
	OUT	(#0x99),A
	LD	HL,#HMMM_CMD		; The HMMC buffer
	LD	C,#0x9B				; And port for indirect access
	LD	A,(HL)				; LD SXL in A
	INC	HL
	INC	HL					; HL pointing to SYL
	ADD	#0x08				; Add 8 to SXL (A) - Border of 16 pixels
	ADD	A,A					; Multiply by 2
	OUT	(C),A				; And send SXL to #32
	LD	A,#0x00				; SXH could be 0
	JR	NC,DO_HMMM.SXH		; If no carry, it is 0
	INC	A					; Otherwise it is 1
DO_HMMM.SXH:	OUT	(C),A	; And send SXH to #33
	LD	A,(HL)				; Load SYL in A
	INC	HL					
	INC	HL					; HL pointing @ DXL
	LD	B,A					; Copy SYL to B
	LD	A,(#VDP_23)			; Get current vertical offset
	ADD	A,B					; Add our SYL to it
	OUT	(C),A				; Send it to #34
	XOR	A					; SYH always 0
	OUT	(C),A				; Send it to #35
	LD	A,(HL)				; LD DXL in A
	INC	HL
	INC	HL					; HL pointing to DYL
	ADD	#0x08				; Add 8 to DXL (A) - Border of 16 pixels
	ADD	A,A					; Multiply by 2
	OUT	(C),A				; And send DXL to #36
	LD	A,#0x00				; DXH could be 0
	JR	NC,DO_HMMM.DXH		; If no carry, it is 0
	INC	A					; Otherwise it is 1
DO_HMMM.DXH:	OUT	(C),A	; And send DXH to #37
	LD	A,(HL)				; Load DYL in A
	INC	HL					
	INC	HL					; HL pointing @ DYL
	LD	B,A					; Copy DYL to B
	LD	A,(#VDP_23)			; Get current vertical offset
	ADD	A,B					; Add our DYL to it
	OUT	(C),A				; Send it to #38
	XOR	A					; DYH always 0
	OUT	(C),A				; Send it to #38
	; And now send the rest of buffer,
	OUTI					; NXL -> #40
	OUTI					; NXH -> #41
	OUTI					; NYL -> #42
	OUTI					; NYH -> #43
	; And now we skip #44 and go to#45 and #46
	LD	A,(HL)				; Load ARG in A
	INC	HL					; HL pointing to CMD
	OUT	(#0x99),A			; Send it
	LD	A,#0xAD				; #45				
	OUT	(#0x99),A			; Send it
	LD	A,(HL)				; Load CMD in A
	OUT	(#0x99),A			; Send it
	LD	A,#0xAE				; #46
	OUT	(#0x99),A			; Send it
	EI
	RET
	
;
;	DATA Portion
;
;	This is where our data is defined
;	

OrgAddress:	.dw	#0x0000

EndAddress:	.dw	#0x0000

SavedCol:	.db	#0x00

SavedRow:	.db	#0x00

CursorCol:	.db	#0x00

CursorRow:	.db	#0x00

CursorVis:	.db	#0x00

BackColor:	.db	#0x00

ForeColor:	.db	#0x07

FontColor:	.db	#0x07

HiLighted:	.db	#0x00


ANSI_M:		.db	#0x00		; If ESC was the previous character will hold ESC, if processing ESC command, will hold [, otherwise 00
ANSI_P:		.dw	#ANSI_S		; Point the next free position in buffer
ANSI_S:		.ds	0x10		; Buffer to hold the ANSI command or data received to print
ANSI_CB:	.db	#0x00		; Wheter we have a callback for cursor position requests or not

Parameters.PST:	.ascii	"0123456789ABCDEF0123456789ABCDEF"
Parameters.TRM:	.db	#0x00
Parameters.PCT:	.db	#0x00
Parameters.PPT:	.dw	#Parameters.PRM
Parameters.PRM:	.db	#0x00,#0x00,#0x00,#0x00,#0x00,#0x00,#0x00,#0x00

ColorTable:	.db	#0x00,#0x0F,#0xF0,#0xFF


HMMC_CMD:
HMMC_CMD.DXL:	.db	#0x00
HMMC_CMD.DXH:	.db	#0x00
HMMC_CMD.DYL:	.db	#0x00
HMMC_CMD.DYH:	.db	#0x00
HMMC_CMD.NXL:	.db	#0x06
HMMC_CMD.NXH:	.db	#0x00
HMMC_CMD.NYL:	.db	#0x08
HMMC_CMD.NYH:	.db	#0x00
HMMC_CMD.CLR:	.db	#0x00
HMMC_CMD.ARG:	.db	#0x00
HMMC_CMD.CMD:	.db	#0xF0



HMMV_CMD:
HMMV_CMD.DXL:	.db	#0x00
HMMV_CMD.DXH:	.db	#0x00
HMMV_CMD.DYL:	.db	#0x00
HMMV_CMD.DYH:	.db	#0x00
HMMV_CMD.NXL:	.db	#0x00
HMMV_CMD.NXH:	.db	#0x00
HMMV_CMD.NYL:	.db	#0x00
HMMV_CMD.NYH:	.db	#0x00
HMMV_CMD.CLR:	.db	#0x00
HMMV_CMD.ARG:	.db	#0x00
HMMV_CMD.CMD:	.db	#0xC0

HMMM_CMD:
HMMM_CMD.SXL:	.db	#0x00
HMMM_CMD.SXH:	.db	#0x00
HMMM_CMD.SYL:	.db	#0x00
HMMM_CMD.SYH:	.db	#0x00
HMMM_CMD.DXL:	.db	#0x00
HMMM_CMD.DXH:	.db	#0x00
HMMM_CMD.DYL:	.db	#0x00
HMMM_CMD.DYH:	.db	#0x00
HMMM_CMD.NXL:	.db	#0x00
HMMM_CMD.NXH:	.db	#0x00
HMMM_CMD.NYL:	.db	#0x00
HMMM_CMD.NYH:	.db	#0x00
HMMM_CMD.ARG:	.db	#0x00
HMMM_CMD.CMD:	.db	#0xD0

ANSI_PAL:
	.db	#0x00,#0x00,#0x50,#0x00,#0x00,#0x05,#0x50,#0x02,#0x05,#0x00,#0x55,#0x00,#0x05,#0x05,#0x55,#0x05
	.db	#0x22,#0x02,#0x72,#0x02,#0x22,#0x07,#0x72,#0x07,#0x27,#0x02,#0x77,#0x02,#0x27,#0x07,#0x77,#0x07

SPRITE_TABLE:
	.db	#0x00,#0x00,#0x00,#0x00 ; Cursor is first, start at line 0, colum 0, uses pattern 0 reserved byte whatever
	.db	#0xD8,#0x00,#0x01,#0x00 ; Next line D8 to make invisible, use pattern 1 (all 0)
	
PATTERN_CURSOR:
	.db	#0x00,#0x00,#0x00,#0x00,#0x00,#0xE0,#0xE0,#0x00
	
PATTERN_INVISIBLE:
	.db	#0x00,#0x00,#0x00,#0x00,#0x00,#0x00,#0x00,#0x00
	
SPRITE_COLORS:
	.db	#0x20,#0x20,#0x20,#0x20,#0x20,#0x27,#0x27,#0x20,#0x20,#0x20,#0x20,#0x20,#0x20,#0x20,#0x20,#0x20
	.db	#0x20,#0x20,#0x20,#0x20,#0x20,#0x20,#0x20,#0x20,#0x20,#0x20,#0x20,#0x20,#0x20,#0x20,#0x20,#0x20

FontData:
	.db #0x00,#0x00,#0x00,#0x00,#0x00,#0x00,#0x00,#0x00
	.db #0x3C,#0x40,#0xA4,#0x80,#0xA4,#0x98,#0x40,#0x3C
	.db #0x3C,#0x7C,#0xD8,#0xFC,#0xFC,#0xD8,#0x64,#0x3C
	.db #0x6C,#0xFC,#0xFC,#0xFC,#0x7C,#0x38,#0x10,#0x00
	.db #0x10,#0x38,#0x7C,#0xFC,#0x7C,#0x38,#0x10,#0x00
	.db #0x10,#0x38,#0x54,#0xFC,#0x54,#0x10,#0x38,#0x00
	.db #0x10,#0x38,#0x7C,#0xFC,#0xFC,#0x10,#0x38,#0x00
	.db #0x00,#0x00,#0x00,#0x30,#0x30,#0x00,#0x00,#0x00
	.db #0xFC,#0xFC,#0xFC,#0xE4,#0xE4,#0xFC,#0xFC,#0xFC
	.db #0x38,#0x44,#0x80,#0x80,#0x80,#0x44,#0x38,#0x00
	.db #0xC4,#0xB8,#0x7C,#0x7C,#0x7C,#0xB8,#0xC4,#0xFC
	.db #0x0C,#0x00,#0x04,#0x78,#0x88,#0x88,#0x88,#0x70
	.db #0x38,#0x44,#0x44,#0x44,#0x38,#0x10,#0x7C,#0x10
	.db #0x30,#0x28,#0x24,#0x24,#0x28,#0x20,#0xE0,#0xC0
	.db #0x3C,#0x24,#0x3C,#0x24,#0x24,#0xE4,#0xDC,#0x18
	.db #0x10,#0x54,#0x38,#0xEC,#0x38,#0x54,#0x10,#0x00
	.db #0x10,#0x10,#0x10,#0x7C,#0x10,#0x10,#0x10,#0x10
	.db #0x10,#0x10,#0x10,#0xFC,#0x00,#0x00,#0x00,#0x00
	.db #0x00,#0x00,#0x00,#0xFC,#0x10,#0x10,#0x10,#0x10
	.db #0x10,#0x10,#0x10,#0xF0,#0x10,#0x10,#0x10,#0x10
	.db #0x10,#0x10,#0x10,#0x1C,#0x10,#0x10,#0x10,#0x10
	.db #0x10,#0x10,#0x10,#0xFC,#0x10,#0x10,#0x10,#0x10
	.db #0x10,#0x10,#0x10,#0x10,#0x10,#0x10,#0x10,#0x10
	.db #0x00,#0x00,#0x00,#0xFC,#0x00,#0x00,#0x00,#0x00
	.db #0x00,#0x00,#0x00,#0x1C,#0x10,#0x10,#0x10,#0x10
	.db #0x00,#0x00,#0x00,#0xF0,#0x10,#0x10,#0x10,#0x10
	.db #0x10,#0x10,#0x10,#0x1C,#0x00,#0x00,#0x00,#0x00
	.db #0x10,#0x10,#0x10,#0xF0,#0x00,#0x00,#0x00,#0x00
	.db #0x80,#0x40,#0x24,#0x18,#0x18,#0x24,#0x40,#0x80
	.db #0x00,#0x00,#0x04,#0x08,#0x10,#0x20,#0x40,#0x80
	.db #0x80,#0x40,#0x20,#0x10,#0x08,#0x04,#0x00,#0x00
	.db #0x00,#0x10,#0x10,#0xFC,#0x10,#0x10,#0x00,#0x00
	.db #0x00,#0x00,#0x00,#0x00,#0x00,#0x00,#0x00,#0x00
	.db #0x20,#0x20,#0x20,#0x20,#0x00,#0x00,#0x20,#0x00
	.db #0x50,#0x50,#0x50,#0x00,#0x00,#0x00,#0x00,#0x00
	.db #0x50,#0x50,#0xF8,#0x50,#0xF8,#0x50,#0x50,#0x00
	.db #0x20,#0x78,#0xA0,#0x70,#0x28,#0xF0,#0x20,#0x00
	.db #0xC0,#0xC8,#0x10,#0x20,#0x40,#0x98,#0x18,#0x00
	.db #0x40,#0xA0,#0x40,#0xA8,#0x90,#0x98,#0x60,#0x00
	.db #0x10,#0x20,#0x40,#0x00,#0x00,#0x00,#0x00,#0x00
	.db #0x10,#0x20,#0x40,#0x40,#0x40,#0x20,#0x10,#0x00
	.db #0x40,#0x20,#0x10,#0x10,#0x10,#0x20,#0x40,#0x00
	.db #0x20,#0xA8,#0x70,#0x20,#0x70,#0xA8,#0x20,#0x00
	.db #0x00,#0x20,#0x20,#0xF8,#0x20,#0x20,#0x00,#0x00
	.db #0x00,#0x00,#0x00,#0x00,#0x00,#0x20,#0x20,#0x40
	.db #0x00,#0x00,#0x00,#0x78,#0x00,#0x00,#0x00,#0x00
	.db #0x00,#0x00,#0x00,#0x00,#0x00,#0x60,#0x60,#0x00
	.db #0x00,#0x00,#0x08,#0x10,#0x20,#0x40,#0x80,#0x00
	.db #0x70,#0x88,#0x98,#0xA8,#0xC8,#0x88,#0x70,#0x00
	.db #0x20,#0x60,#0xA0,#0x20,#0x20,#0x20,#0xF8,#0x00
	.db #0x70,#0x88,#0x08,#0x10,#0x60,#0x80,#0xF8,#0x00
	.db #0x70,#0x88,#0x08,#0x30,#0x08,#0x88,#0x70,#0x00
	.db #0x10,#0x30,#0x50,#0x90,#0xF8,#0x10,#0x10,#0x00
	.db #0xF8,#0x80,#0xE0,#0x10,#0x08,#0x10,#0xE0,#0x00
	.db #0x30,#0x40,#0x80,#0xF0,#0x88,#0x88,#0x70,#0x00
	.db #0xF8,#0x88,#0x10,#0x20,#0x20,#0x20,#0x20,#0x00
	.db #0x70,#0x88,#0x88,#0x70,#0x88,#0x88,#0x70,#0x00
	.db #0x70,#0x88,#0x88,#0x78,#0x08,#0x10,#0x60,#0x00
	.db #0x00,#0x00,#0x20,#0x00,#0x00,#0x20,#0x00,#0x00
	.db #0x00,#0x00,#0x20,#0x00,#0x00,#0x20,#0x20,#0x40
	.db #0x18,#0x30,#0x60,#0xC0,#0x60,#0x30,#0x18,#0x00
	.db #0x00,#0x00,#0xF8,#0x00,#0xF8,#0x00,#0x00,#0x00
	.db #0xC0,#0x60,#0x30,#0x18,#0x30,#0x60,#0xC0,#0x00
	.db #0x70,#0x88,#0x08,#0x10,#0x20,#0x00,#0x20,#0x00
	.db #0x70,#0x88,#0x08,#0x68,#0xA8,#0xA8,#0x70,#0x00
	.db #0x20,#0x50,#0x88,#0x88,#0xF8,#0x88,#0x88,#0x00
	.db #0xF0,#0x48,#0x48,#0x70,#0x48,#0x48,#0xF0,#0x00
	.db #0x30,#0x48,#0x80,#0x80,#0x80,#0x48,#0x30,#0x00
	.db #0xE0,#0x50,#0x48,#0x48,#0x48,#0x50,#0xE0,#0x00
	.db #0xF8,#0x80,#0x80,#0xF0,#0x80,#0x80,#0xF8,#0x00
	.db #0xF8,#0x80,#0x80,#0xF0,#0x80,#0x80,#0x80,#0x00
	.db #0x70,#0x88,#0x80,#0xB8,#0x88,#0x88,#0x70,#0x00
	.db #0x88,#0x88,#0x88,#0xF8,#0x88,#0x88,#0x88,#0x00
	.db #0x70,#0x20,#0x20,#0x20,#0x20,#0x20,#0x70,#0x00
	.db #0x38,#0x10,#0x10,#0x10,#0x90,#0x90,#0x60,#0x00
	.db #0x88,#0x90,#0xA0,#0xC0,#0xA0,#0x90,#0x88,#0x00
	.db #0x80,#0x80,#0x80,#0x80,#0x80,#0x80,#0xF8,#0x00
	.db #0x88,#0xD8,#0xA8,#0xA8,#0x88,#0x88,#0x88,#0x00
	.db #0x88,#0xC8,#0xC8,#0xA8,#0x98,#0x98,#0x88,#0x00
	.db #0x70,#0x88,#0x88,#0x88,#0x88,#0x88,#0x70,#0x00
	.db #0xF0,#0x88,#0x88,#0xF0,#0x80,#0x80,#0x80,#0x00
	.db #0x70,#0x88,#0x88,#0x88,#0xA8,#0x90,#0x68,#0x00
	.db #0xF0,#0x88,#0x88,#0xF0,#0xA0,#0x90,#0x88,#0x00
	.db #0x70,#0x88,#0x80,#0x70,#0x08,#0x88,#0x70,#0x00
	.db #0xF8,#0x20,#0x20,#0x20,#0x20,#0x20,#0x20,#0x00
	.db #0x88,#0x88,#0x88,#0x88,#0x88,#0x88,#0x70,#0x00
	.db #0x88,#0x88,#0x88,#0x88,#0x50,#0x50,#0x20,#0x00
	.db #0x88,#0x88,#0x88,#0xA8,#0xA8,#0xD8,#0x88,#0x00
	.db #0x88,#0x88,#0x50,#0x20,#0x50,#0x88,#0x88,#0x00
	.db #0x88,#0x88,#0x88,#0x70,#0x20,#0x20,#0x20,#0x00
	.db #0xF8,#0x08,#0x10,#0x20,#0x40,#0x80,#0xF8,#0x00
	.db #0x70,#0x40,#0x40,#0x40,#0x40,#0x40,#0x70,#0x00
	.db #0x00,#0x00,#0x80,#0x40,#0x20,#0x10,#0x08,#0x00
	.db #0x70,#0x10,#0x10,#0x10,#0x10,#0x10,#0x70,#0x00
	.db #0x20,#0x50,#0x88,#0x00,#0x00,#0x00,#0x00,#0x00
	.db #0x00,#0x00,#0x00,#0x00,#0x00,#0x00,#0xF8,#0x00
	.db #0x40,#0x20,#0x10,#0x00,#0x00,#0x00,#0x00,#0x00
	.db #0x00,#0x00,#0x70,#0x08,#0x78,#0x88,#0x78,#0x00
	.db #0x80,#0x80,#0xB0,#0xC8,#0x88,#0xC8,#0xB0,#0x00
	.db #0x00,#0x00,#0x70,#0x88,#0x80,#0x88,#0x70,#0x00
	.db #0x08,#0x08,#0x68,#0x98,#0x88,#0x98,#0x68,#0x00
	.db #0x00,#0x00,#0x70,#0x88,#0xF8,#0x80,#0x70,#0x00
	.db #0x10,#0x28,#0x20,#0xF8,#0x20,#0x20,#0x20,#0x00
	.db #0x00,#0x00,#0x68,#0x98,#0x98,#0x68,#0x08,#0x70
	.db #0x80,#0x80,#0xF0,#0x88,#0x88,#0x88,#0x88,#0x00
	.db #0x20,#0x00,#0x60,#0x20,#0x20,#0x20,#0x70,#0x00
	.db #0x10,#0x00,#0x30,#0x10,#0x10,#0x10,#0x90,#0x60
	.db #0x40,#0x40,#0x48,#0x50,#0x60,#0x50,#0x48,#0x00
	.db #0x60,#0x20,#0x20,#0x20,#0x20,#0x20,#0x70,#0x00
	.db #0x00,#0x00,#0xD0,#0xA8,#0xA8,#0xA8,#0xA8,#0x00
	.db #0x00,#0x00,#0xB0,#0xC8,#0x88,#0x88,#0x88,#0x00
	.db #0x00,#0x00,#0x70,#0x88,#0x88,#0x88,#0x70,#0x00
	.db #0x00,#0x00,#0xB0,#0xC8,#0xC8,#0xB0,#0x80,#0x80
	.db #0x00,#0x00,#0x68,#0x98,#0x98,#0x68,#0x08,#0x08
	.db #0x00,#0x00,#0xB0,#0xC8,#0x80,#0x80,#0x80,#0x00
	.db #0x00,#0x00,#0x78,#0x80,#0xF0,#0x08,#0xF0,#0x00
	.db #0x40,#0x40,#0xF0,#0x40,#0x40,#0x48,#0x30,#0x00
	.db #0x00,#0x00,#0x90,#0x90,#0x90,#0x90,#0x68,#0x00
	.db #0x00,#0x00,#0x88,#0x88,#0x88,#0x50,#0x20,#0x00
	.db #0x00,#0x00,#0x88,#0xA8,#0xA8,#0xA8,#0x50,#0x00
	.db #0x00,#0x00,#0x88,#0x50,#0x20,#0x50,#0x88,#0x00
	.db #0x00,#0x00,#0x88,#0x88,#0x98,#0x68,#0x08,#0x70
	.db #0x00,#0x00,#0xF8,#0x10,#0x20,#0x40,#0xF8,#0x00
	.db #0x18,#0x20,#0x20,#0x40,#0x20,#0x20,#0x18,#0x00
	.db #0x20,#0x20,#0x20,#0x00,#0x20,#0x20,#0x20,#0x00
	.db #0xC0,#0x20,#0x20,#0x10,#0x20,#0x20,#0xC0,#0x00
	.db #0x40,#0xA8,#0x10,#0x00,#0x00,#0x00,#0x00,#0x00
	.db #0x00,#0x20,#0x50,#0x88,#0x88,#0x88,#0xF8,#0x00
	.db #0x70,#0x88,#0x80,#0x80,#0x88,#0x70,#0x20,#0x60
	.db #0x90,#0x00,#0x00,#0x90,#0x90,#0x90,#0x68,#0x00
	.db #0x10,#0x20,#0x70,#0x88,#0xF8,#0x80,#0x70,#0x00
	.db #0x20,#0x50,#0x70,#0x08,#0x78,#0x88,#0x78,#0x00
	.db #0x48,#0x00,#0x70,#0x08,#0x78,#0x88,#0x78,#0x00
	.db #0x20,#0x10,#0x70,#0x08,#0x78,#0x88,#0x78,#0x00
	.db #0x20,#0x00,#0x70,#0x08,#0x78,#0x88,#0x78,#0x00
	.db #0x00,#0x70,#0x80,#0x80,#0x80,#0x70,#0x10,#0x60
	.db #0x20,#0x50,#0x70,#0x88,#0xF8,#0x80,#0x70,#0x00
	.db #0x50,#0x00,#0x70,#0x88,#0xF8,#0x80,#0x70,#0x00
	.db #0x20,#0x10,#0x70,#0x88,#0xF8,#0x80,#0x70,#0x00
	.db #0x50,#0x00,#0x00,#0x60,#0x20,#0x20,#0x70,#0x00
	.db #0x20,#0x50,#0x00,#0x60,#0x20,#0x20,#0x70,#0x00
	.db #0x40,#0x20,#0x00,#0x60,#0x20,#0x20,#0x70,#0x00
	.db #0x50,#0x00,#0x20,#0x50,#0x88,#0xF8,#0x88,#0x00
	.db #0x20,#0x00,#0x20,#0x50,#0x88,#0xF8,#0x88,#0x00
	.db #0x10,#0x20,#0xF8,#0x80,#0xF0,#0x80,#0xF8,#0x00
	.db #0x00,#0x00,#0x6C,#0x10,#0x7C,#0x90,#0x6C,#0x00
	.db #0x3C,#0x50,#0x90,#0x9C,#0xF0,#0x90,#0x9C,#0x00
	.db #0x60,#0x90,#0x00,#0x60,#0x90,#0x90,#0x60,#0x00
	.db #0x90,#0x00,#0x00,#0x60,#0x90,#0x90,#0x60,#0x00
	.db #0x40,#0x20,#0x00,#0x60,#0x90,#0x90,#0x60,#0x00
	.db #0x40,#0xA0,#0x00,#0xA0,#0xA0,#0xA0,#0x50,#0x00
	.db #0x40,#0x20,#0x00,#0xA0,#0xA0,#0xA0,#0x50,#0x00
	.db #0x90,#0x00,#0x90,#0x90,#0xB0,#0x50,#0x10,#0xE0
	.db #0x50,#0x00,#0x70,#0x88,#0x88,#0x88,#0x70,#0x00
	.db #0x50,#0x00,#0x88,#0x88,#0x88,#0x88,#0x70,#0x00
	.db #0x20,#0x20,#0x78,#0x80,#0x80,#0x78,#0x20,#0x20
	.db #0x18,#0x24,#0x20,#0xF8,#0x20,#0xE0,#0x5C,#0x00
	.db #0x88,#0x50,#0x20,#0xF8,#0x20,#0xF8,#0x20,#0x00
	.db #0xC0,#0xA0,#0xA0,#0xC8,#0x9C,#0x88,#0x88,#0x8C
	.db #0x18,#0x20,#0x20,#0xF8,#0x20,#0x20,#0x20,#0x40
	.db #0x10,#0x20,#0x70,#0x08,#0x78,#0x88,#0x78,#0x00
	.db #0x10,#0x20,#0x00,#0x60,#0x20,#0x20,#0x70,#0x00
	.db #0x20,#0x40,#0x00,#0x60,#0x90,#0x90,#0x60,#0x00
	.db #0x20,#0x40,#0x00,#0x90,#0x90,#0x90,#0x68,#0x00
	.db #0x50,#0xA0,#0x00,#0xA0,#0xD0,#0x90,#0x90,#0x00
	.db #0x28,#0x50,#0x00,#0xC8,#0xA8,#0x98,#0x88,#0x00
	.db #0x00,#0x70,#0x08,#0x78,#0x88,#0x78,#0x00,#0xF8
	.db #0x00,#0x60,#0x90,#0x90,#0x90,#0x60,#0x00,#0xF0
	.db #0x20,#0x00,#0x20,#0x40,#0x80,#0x88,#0x70,#0x00
	.db #0x00,#0x00,#0x00,#0xF8,#0x80,#0x80,#0x00,#0x00
	.db #0x00,#0x00,#0x00,#0xF8,#0x08,#0x08,#0x00,#0x00
	.db #0x84,#0x88,#0x90,#0xA8,#0x54,#0x84,#0x08,#0x1C
	.db #0x84,#0x88,#0x90,#0xA8,#0x58,#0xA8,#0x3C,#0x08
	.db #0x20,#0x00,#0x00,#0x20,#0x20,#0x20,#0x20,#0x00
	.db #0x00,#0x00,#0x24,#0x48,#0x90,#0x48,#0x24,#0x00
	.db #0x00,#0x00,#0x90,#0x48,#0x24,#0x48,#0x90,#0x00
	.db #0x90,#0x48,#0x24,#0x90,#0x48,#0x24,#0x90,#0x48
	.db #0xA8,#0x54,#0xA8,#0x54,#0xA8,#0x54,#0xA8,#0x54
	.db #0x6C,#0xB4,#0xD8,#0x6C,#0xB4,#0xD8,#0x6C,#0xB4
	.db #0x20,#0x20,#0x20,#0x20,#0x20,#0x20,#0x20,#0x20
	.db #0x20,#0x20,#0x20,#0xE0,#0x20,#0x20,#0x20,#0x20
	.db #0x20,#0x20,#0xE0,#0x20,#0xE0,#0x20,#0x20,#0x20
	.db #0x50,#0x50,#0x50,#0xD0,#0x50,#0x50,#0x50,#0x50
	.db #0x00,#0x00,#0x00,#0xF0,#0x50,#0x50,#0x50,#0x50
	.db #0x00,#0x00,#0xE0,#0x20,#0xE0,#0x20,#0x20,#0x20
	.db #0x50,#0x50,#0xD0,#0x10,#0xD0,#0x50,#0x50,#0x50
	.db #0x50,#0x50,#0x50,#0x50,#0x50,#0x50,#0x50,#0x50
	.db #0x00,#0x00,#0xF0,#0x10,#0xD0,#0x50,#0x50,#0x50
	.db #0x50,#0x50,#0xD0,#0x10,#0xF0,#0x00,#0x00,#0x00
	.db #0x50,#0x50,#0x50,#0xF0,#0x00,#0x00,#0x00,#0x00
	.db #0x20,#0x20,#0xE0,#0x20,#0xE0,#0x00,#0x00,#0x00
	.db #0x00,#0x00,#0x00,#0xE0,#0x20,#0x20,#0x20,#0x20
	.db #0x20,#0x20,#0x20,#0x3C,#0x00,#0x00,#0x00,#0x00
	.db #0x20,#0x20,#0x20,#0xFC,#0x00,#0x00,#0x00,#0x00
	.db #0x00,#0x00,#0x00,#0xFC,#0x20,#0x20,#0x20,#0x20
	.db #0x20,#0x20,#0x20,#0x3C,#0x20,#0x20,#0x20,#0x20
	.db #0x00,#0x00,#0x00,#0xFC,#0x00,#0x00,#0x00,#0x00
	.db #0x20,#0x20,#0x20,#0xFC,#0x20,#0x20,#0x20,#0x20
	.db #0x20,#0x20,#0x3C,#0x20,#0x3C,#0x20,#0x20,#0x20
	.db #0x50,#0x50,#0x50,#0x5C,#0x50,#0x50,#0x50,#0x50
	.db #0x50,#0x50,#0x5C,#0x40,#0x7C,#0x00,#0x00,#0x00
	.db #0x00,#0x00,#0x7C,#0x40,#0x5C,#0x50,#0x50,#0x50
	.db #0x50,#0x50,#0xDC,#0x00,#0xFC,#0x00,#0x00,#0x00
	.db #0x00,#0x00,#0xFC,#0x00,#0xDC,#0x50,#0x50,#0x50
	.db #0x50,#0x50,#0x5C,#0x40,#0x5C,#0x50,#0x50,#0x50
	.db #0x00,#0x00,#0xFC,#0x00,#0xFC,#0x00,#0x00,#0x00
	.db #0x50,#0x50,#0xDC,#0x00,#0xDC,#0x50,#0x50,#0x50
	.db #0x20,#0x20,#0xFC,#0x00,#0xFC,#0x00,#0x00,#0x00
	.db #0x50,#0x50,#0x50,#0xFC,#0x00,#0x00,#0x00,#0x00
	.db #0x00,#0x00,#0xFC,#0x00,#0xFC,#0x20,#0x20,#0x20
	.db #0x00,#0x00,#0x00,#0xFC,#0x50,#0x50,#0x50,#0x50
	.db #0x50,#0x50,#0x50,#0x7C,#0x00,#0x00,#0x00,#0x00
	.db #0x20,#0x20,#0x3C,#0x20,#0x3C,#0x00,#0x00,#0x00
	.db #0x00,#0x00,#0x3C,#0x20,#0x3C,#0x20,#0x20,#0x20
	.db #0x00,#0x00,#0x00,#0x7C,#0x50,#0x50,#0x50,#0x50
	.db #0x50,#0x50,#0x50,#0xFC,#0x50,#0x50,#0x50,#0x50
	.db #0x20,#0x20,#0xFC,#0x20,#0xFC,#0x20,#0x20,#0x20
	.db #0x20,#0x20,#0x20,#0xE0,#0x00,#0x00,#0x00,#0x00
	.db #0x00,#0x00,#0x00,#0x3C,#0x20,#0x20,#0x20,#0x20
	.db #0xFC,#0xFC,#0xFC,#0xFC,#0xFC,#0xFC,#0xFC,#0xFC
	.db #0x00,#0x00,#0x00,#0x00,#0xFC,#0xFC,#0xFC,#0xFC
	.db #0xE0,#0xE0,#0xE0,#0xE0,#0xE0,#0xE0,#0xE0,#0xE0
	.db #0x1C,#0x1C,#0x1C,#0x1C,#0x1C,#0x1C,#0x1C,#0x1C
	.db #0xFC,#0xFC,#0xFC,#0xFC,#0x00,#0x00,#0x00,#0x00
	.db #0x00,#0x00,#0x68,#0x90,#0x90,#0x90,#0x68,#0x00
	.db #0x30,#0x48,#0x48,#0x70,#0x48,#0x48,#0x70,#0xC0
	.db #0xF8,#0x88,#0x80,#0x80,#0x80,#0x80,#0x80,#0x00
	.db #0xF8,#0x50,#0x50,#0x50,#0x50,#0x50,#0x98,#0x00
	.db #0xF8,#0x88,#0x40,#0x20,#0x40,#0x88,#0xF8,#0x00
	.db #0x00,#0x00,#0x78,#0x90,#0x90,#0x90,#0x60,#0x00
	.db #0x00,#0x50,#0x50,#0x50,#0x50,#0x68,#0x80,#0x80
	.db #0x00,#0x50,#0xA0,#0x20,#0x20,#0x20,#0x20,#0x00
	.db #0xF8,#0x20,#0x70,#0xA8,#0xA8,#0x70,#0x20,#0xF8
	.db #0x20,#0x50,#0x88,#0xF8,#0x88,#0x50,#0x20,#0x00
	.db #0x70,#0x88,#0x88,#0x88,#0x50,#0x50,#0xD8,#0x00
	.db #0x30,#0x40,#0x40,#0x20,#0x50,#0x50,#0x50,#0x20
	.db #0x00,#0x00,#0x00,#0x50,#0xA8,#0xA8,#0x50,#0x00
	.db #0x08,#0x70,#0xA8,#0xA8,#0xA8,#0x70,#0x80,#0x00
	.db #0x38,#0x40,#0x80,#0xF8,#0x80,#0x40,#0x38,#0x00
	.db #0x70,#0x88,#0x88,#0x88,#0x88,#0x88,#0x88,#0x00
	.db #0x00,#0xF8,#0x00,#0xF8,#0x00,#0xF8,#0x00,#0x00
	.db #0x20,#0x20,#0xF8,#0x20,#0x20,#0x00,#0xF8,#0x00
	.db #0xC0,#0x30,#0x08,#0x30,#0xC0,#0x00,#0xF8,#0x00
	.db #0x18,#0x60,#0x80,#0x60,#0x18,#0x00,#0xF8,#0x00
	.db #0x10,#0x28,#0x20,#0x20,#0x20,#0x20,#0x20,#0x20
	.db #0x20,#0x20,#0x20,#0x20,#0x20,#0x20,#0xA0,#0x40
	.db #0x00,#0x20,#0x00,#0xF8,#0x00,#0x20,#0x00,#0x00
	.db #0x00,#0x50,#0xA0,#0x00,#0x50,#0xA0,#0x00,#0x00
	.db #0x00,#0x18,#0x24,#0x24,#0x18,#0x00,#0x00,#0x00
	.db #0x00,#0x30,#0x78,#0x78,#0x30,#0x00,#0x00,#0x00
	.db #0x00,#0x00,#0x00,#0x00,#0x30,#0x00,#0x00,#0x00
	.db #0x04,#0x04,#0x08,#0x08,#0x90,#0x70,#0x20,#0x00
	.db #0xA0,#0x50,#0x50,#0x50,#0x00,#0x00,#0x00,#0x00
	.db #0x40,#0xA0,#0x20,#0x40,#0xE0,#0x00,#0x00,#0x00
	.db #0x00,#0x00,#0x30,#0x30,#0x30,#0x30,#0x00,#0x00
	.db #0xFC,#0xFC,#0xFC,#0xFC,#0xFC,#0xFC,#0xFC,#0xFC