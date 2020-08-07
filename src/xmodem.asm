romst   equ     $c000
src_end	equ	$48

; Hardware registers
config  equ     $ff64
;config	equ	$2800
fcntrl  equ     config
bank_lo equ     config+1
bank_hi equ     config+2


; XMODEM constants
SOH     equ     $1
ACK     equ     $6
EOT     equ     $4
NAK     equ     $15
CAN	equ	$18

	org	$600
	jsr	clrscn
	ldx	#xmhelo
	jsr	draw

xmodem  orcc	#$50
	ldd	#$0101
        sta     bank_hi
        stb     bank_lo

        ; XMODEM download
        ldx     #romst
        stx     target
        clra                    ; Reset block number
        sta     lblk
	ldx	#xmtmo
snak    jsr	updstat
        lda     #NAK            ; Send a NAK
        jsr     putc
1       ldx     #btype          ; Read packet
        ldy     #132
	clr	btype		; Reset packet type
        jsr     DWRead
        beq     2f
	ldx	#xmtmo		; Prepare to show timeout message
        lda     btype		; Short packet
        cmpa    #EOT            ; Is it EOT?
        beq     done
        bra     snak
2       ldx	#xmerr		; Prepare to show error message
	lda     btype
        cmpa    #SOH            ; Is it SOH?
	bne	snak		; Unknown packet header
        lda     blk             ; Test block number
        adda    iblk
        coma
	bne	snak		; Corrupted block number
        lda     blk
        suba    lblk
        beq     sack            ; Resend of previous block - ignore
        deca
	bne	snak		; Wrong block #
        tfr     y,d             ; B=checksum of all 132 bytes
                                ; SOT+blk+blki = 0 always
        subb    cksum           ; So we just need to subtract the checksum
        cmpb    cksum           ; And compare to itself again
	bne	snak		; Checksum error
	ldx	#xmrecv		; Packet good - show OK message
	jsr	draw
        inc     lblk
	ldx	#bdata
	ldu	#128
	ldy	target
	jsr	bcheck		; Blank check
	bne	bchkerr
        jsr     pgmblk          ; Program the packet
        bne     pgmerr
	sty	target
	cmpy	#$d000
	blo	sack
	lda	bank_hi		; End of window, advance to next bank
	ldb	bank_lo
	addd	#1
	sta	bank_hi
	stb	bank_lo
	ldy	#romst
	sty	target
sack    jsr	updstat
	lda     #ACK            ; Send ACK and read next packet
        bsr     putc
        lbra     1b

done    lda     #ACK		; Send final ack
	bsr	putc
	andcc 	#$af		; Enable interrupts
	ldx	#xmdone
	jsr	draw
	ldx	#xmany
	jsr	draw
	rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Write A character to serial port
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
putc    sta     $6
        ldx     #6
        ldy     #1
        jmp     DWWrite

pgmerr	ldx	#xmpgme
	bra	cancel

bchkerr	ldx	#xmbchk
	bra	cancel

cancel	jsr	draw
	ldx	#cans
	ldy	#10
	jsr	DWWrite
	rts

	include	"screen.asm"

updstat	jsr	draw		; Print status message
	lda	bank_hi		; Update bank
	ldb	bank_lo
	rowcol	3,6
	jsr	drawwrd
	ldd	target		; Update address
	rowcol	3,16+6
	jsr	drawwrd
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
	

        include "serio.asm"
;	include	"pgmblk.asm"
pgmblk	leay	128,y
	clra
	rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Resources
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
xmhelo	stext	2,1, "RECEIVING XMODEM 38400-N-8-1"
	stext	3,1, "BANK"
	stext	3,16,"ADDR"
	stend
xmtmo	stext1	4,1, "TIMEOUT "
xmrecv	stext1	4,1, "RECEIVED"
xmerr	stext1	4,1, "ERROR   "
xmdone	stext1	4,1, "DONE    "
xmbchk	stext1	4,1, "BLANK CHECK FAILED"
xmpgme	stext1	4,1, "PROGRAMMING ERROR"
xmany	stext1	5,1, "PRESS ANY KEY TO EXIT"
cans	fill	CAN,10

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Variables
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        org     $01d1   ; Cassette file name buffer
lblk    rmb     1   ; Current block counter
target  rmb     2   ; ROM address to write to

        org     $0200   ; Cassette data buffer
; XMODEM packet
btype   rmb     1
blk     rmb     1
iblk    rmb     1
bdata   rmb     128
cksum   rmb     1

