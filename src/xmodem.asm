romst   equ     $c000
romend	equ	$d000

; Hardware registers
config  equ     $ff64
;config	equ	$2800
fcntrl  equ     config
bank_lo equ     config+1
bank_hi equ     config+2

	org	$600
	clr	bank_hi
	lda	#$30
	sta	bank_lo
	jsr	clrscn
	ldx	#romst		; Reset target address
	stx	target
	ldx	#xmhelo
	jsr	draw

	jsr	xminit
loop	jsr	[$a000]		; Abort on keypress
	bne	done
	jsr	xmread
	jsr	updstat		; Update screen
	cmpa	#xdone
	beq	done
	cmpa	#xok
	bne	loop
	; TODO - actual work
	ldy	target
	jsr	bcheck
	bne	notempty
	ldx	target		; Advance target to next page
	leax	128,x
	cmpx	#romend
	blo	2f
	ldx	#romst
	inc	bank_lo		; Hit end, move to next bank
	bne	2f
	inc	bank_hi
2	stx	target
	bra	loop

done	ldx	#xmdone
	jsr	draw
	ldx	#xmany
	jsr	draw
	rts

notempty	ldx	#xmbchk
	jsr	draw
	jsr	xcancel
	rts

	include	"screen.asm"

updstat	pshs	a
	ldx	#xmsgs		; Look up status msg in table
	tfr	a,b
	lslb
	abx
	ldx	0,x
	jsr	draw		; Print status message
	lda	bank_hi		; Update bank
	ldb	bank_lo
	rowcol	3,7
	jsr	drawwrd
	ldd	target		; Update address
	rowcol	3,16+6
	jsr	drawwrd
	puls	a
	rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Perform blank check
;
; Y = target register
;
; Returns Z=blank, NZ=dirty
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
bcheck	ldb	#128
1	lda	,y+	; Read byte
	coma		; Is it $FF?
	bne	2f	; Fail if not
	decb
	bne	1b
	leay	-128,y	; Reset to beginning
	clra
2	rts
	
        include "xmlib.asm"
;	include	"pgmblk.asm"
pgmblk	leay	128,y
	clra
	rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Resources
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
xmhelo	stext	1,1, "RECEIVING XMODEM 38400-N-8-1"
	stext	3,1, "BANK:"
	stext	3,16,"ADDR:"
	stext	5,1, "STATUS:"
	stend
xmtmo	stext1	5,10, "TIMEOUT "
xmrecv	stext1	5,10, "RECEIVED"
xmerr	stext1	5,10, "ERROR   "
xmdone	stext1	5,10, "DONE    "
xmrsnd	stext1	5,10, "RESEND  "
xmbchk	stext1	5,10, "ROM NOT BLANK"
xmpgme	stext1	5,10, "PROGRAMMING ERROR"
xmany	stext1	5,10, "PRESS ANY KEY TO EXIT"
xmsgs	fdb	xmdone,xmrecv,xmtmo,xmerr,xmrsnd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Variables
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
target	rmb	2
