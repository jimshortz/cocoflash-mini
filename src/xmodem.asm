
; XMODEM mode

xmodem 	jsr	2f
	ldx	#xanyky
	jsr	draw
1	jsr	[polcat]
	beq	1b
	jmp	mmode
2	jsr	clrscn
	ldx	#rom  		; Reset target address
	stx	target
	ldx	#xhello
	jsr	draw
	jsr	xminit
	lda	#XMTMO
	bsr	updstat
3	jsr	[polcat]	; Abort on Q keypress
	cmpa	#'Q'
	beq	5f
	jsr	xmread
	bsr	updstat		; Update screen
	cmpa	#XMDONE
	beq	3f
	cmpa	#XMOK
	bne	3b
	ldy	target
	jsr	bcheck
	bne	4f
	ldx	#bdata		; Copy 128 bytes into ROM
	ldy	target
	ldd	#128
	jsr	pgmblk
	bne	7f
	ldx	#xrecv		; Change msg to "RECEIVING"
	jsr	draw
	ldx	target		; Advance target to next page
	leax	128,x
	cmpx	#romend
	blo	2f
	ldx	#rom  
	inc	bank_lo		; Hit end, move to next bank
	bne	2f
	inc	bank_hi
2	stx	target
	bra	3b
3	ldx	#xdone
	jsr	draw
	rts
7	ldx	#xpgmerr
	jsr	draw
	bra	5f
4	ldx	#xbchk
	jsr	draw
5	jsr	xcancel
	rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Updates screen with current download status
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Resources
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
xhello	stext	1,1, "RECEIVING XMODEM 38400-N-8-1"
	stext	3,1, "BANK:"
	stext	3,16,"ADDR:"
	stext	5,1, "STATUS:"
	stext	7,8, "HOLD Q TO ABORT"
	stend
xbchk	stext1	5,10, "ROM NOT BLANK"
xpgmerr	stext1	5,10, "PROGRAMMING ERROR"
xanyky	stext1	7,(32-22)/2, "PRESS ANY KEY TO EXIT"
xtmo	stext1	5,10, "WAITING     "
xpgm	stext1	5,10, "PROGRAMMING "
xerr	stext1	5,10, "XFER ERROR  "
xdone	stext1	5,10, "DONE        "
xrsnd	stext1	5,10, "SKIPPING    "
xrecv	stext1  5,10, "RECEIVING   "
xmsgs	fdb	xdone,xpgm,xtmo,xerr,xrsnd

