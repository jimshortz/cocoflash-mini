
; XMODEM mode

xmodem 	jsr	2f
	ldx	#xmany
	jsr	draw
1	jsr	[polcat]
	beq	1b
	jmp	mmode
2	jsr	clrscn
	ldx	#rom  		; Reset target address
	stx	target
	ldx	#xmhelo
	jsr	draw
	jsr	xminit
loop	jsr	[$a000]		; Abort on keypress
	bne	5f
	jsr	xmread
	jsr	updstat		; Update screen
	cmpa	#xdone
	beq	3f
	cmpa	#xok
	bne	loop
	ldy	target
	jsr	bcheck
	bne	4f
	ldx	#bdata		; Copy 128 bytes into ROM
	ldy	target
	ldd	#128
	jsr	pgmblk
	bne	7f
	ldx	target		; Advance target to next page
	leax	128,x
	cmpx	#romend
	blo	2f
	ldx	#rom  
	inc	bank_lo		; Hit end, move to next bank
	bne	2f
	inc	bank_hi
2	stx	target
	bra	loop
3	ldx	#xmdone
	jsr	draw
	rts
7	ldx	#xmpgme
	jsr	draw
	bra	5f
4	ldx	#xmbchk
	jsr	draw
5	jsr	xcancel
	rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

; STUB
;pgmblk	leay	128,y
;	clra
;	rts

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
xmany	stext1	7,6, "PRESS ANY KEY TO EXIT"
xmsgs	fdb	xmdone,xmrecv,xmtmo,xmerr,xmrsnd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Variables
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
target	rmb	2
