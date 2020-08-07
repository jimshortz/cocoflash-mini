; Memory locations

text    equ     $0400           ; Text screen
textend equ     text+16*32

; Defines static text (row, column, text)
stext   macro
        fdb     \1*32+\2
        fcn     \3
        endm

stext1	macro
        fdb     \1*32+\2
        fcn     \3
	fdb	$ffff
	endm

stend	macro
	fdb	$ffff
	endm

rowcol	macro
	ldy	#text+32*\1+\2
	endm

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Clears the screen
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
clrscn  
        ldx     #text
        lda     #$60
1       sta     ,x+
        cmpx    #textend
        bne     1b
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Draws static text
; X - pointer to text block (as established by stext macro)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
draw    ldy     ,x++
        cmpy    #$ffff          ; Reached the end?
        beq     2f
        leay    text,y
1       lda     ,x+
        beq     draw
        ora     #$40
        sta     ,y+
        bra     1b
2       rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Draw a word (2 bytes) on the screen in hex
;
; Inputs:
;   D - Word to draw
;   Y - Location to draw to
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
drawwrd bsr     drawbyt
        exg     a,b
        ; Fall through to drawbyt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Draw a byte on the screen in hex
;
; Inputs:
;   A - Byte to draw
;   Y - Location to draw to
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
drawbyt pshs    a
        lsra
        lsra
        lsra
        lsra
        bsr     drawnyb
        puls    a
        ; Fall through to drawnyb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Draw a nybble on the screen in hex
;
; Inputs:
;   A - Nybble to draw (lo)
;   Y - Location to draw to
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
drawnyb anda    #$0f
        cmpa    #10
        bge     1f
        adda    #$70
        bra     2f
1       adda    #'A'-10
2       sta     ,y+
        rts

