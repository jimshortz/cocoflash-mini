; xread responses
xdone	equ	0		; End of file received
xok	equ	1		; Valid data received
xtmo	equ	2		; Timeout receiving data
xerr	equ	3		; Checksum/protocol error
xresend	equ	4		; Extraneous block resent

; XMODEM constants
SOH     equ     $1
ACK     equ     $6
EOT     equ     $4
NAK     equ     $15
CAN	equ	$18

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
xminit 	orcc	#$50
	clr	lblk 		; Reset block number
	lda	#NAK
	sta	xresp
	rts

	include	"serio.asm"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
xmread	clr	btype		; Reset block type
	ldx	#xresp
	ldy	#1
	jsr	DWWrite
        ldx     #btype          ; Read packet
        ldy     #132
        jsr     DWRead
        beq     xcheck		; Full-length packet received
        lda     btype		; Short packet
        cmpa    #EOT            ; Is it EOT?
        beq     xfinish
	lda	#xtmo		; Timeout
	ldb	#NAK
	bra	xout

xcheck	lda     btype
        cmpa    #SOH            ; Is it SOH?
	bne	snak		; Unknown packet header
        lda     blk             ; Test block number
        adda    iblk
        coma
	bne	snak		; Corrupted block number
        lda     blk
        suba    lblk		; Compare to last recvd block
	bne	2f
	ldb	#ACK		; Previous block was resent - ACK and ignore
	lda	#xresend
	bra	xout
2	deca			; Next block?
	bne	snak		; Wrong block #
        tfr     y,d             ; B=checksum of all 132 bytes
                                ; SOT+blk+blki = 0 always
        subb    cksum           ; So we just need to subtract the checksum
        cmpb    cksum           ; And compare to itself again
	bne	snak		; Checksum error
	inc	lblk		; Bump last block counter
	ldb	#ACK		; Block received OK
	lda	#xok
xout	stb	xresp
	ldx	#bdata
	rts

snak	ldb	#NAK
	lda	#xerr
	bra	xout

xfinish	lda	#ACK
	sta	xresp
	ldx	#xresp
	ldy	#1
	jsr	DWWrite
	lda	#xdone
	rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
xcancel	ldx	#xcans
	ldy	#10
	jsr	DWWrite
	rts

xcans	fill	CAN,10

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Variables
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        org     $01d1   ; Cassette file name buffer
lblk    rmb     1   	; Current block counter
xresp	rmb	1

        org     $0200   ; Cassette data buffer
; XMODEM packet
btype   rmb     1
blk     rmb     1
iblk    rmb     1
bdata   rmb     128
cksum   rmb     1

