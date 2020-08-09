; xread responses
XMDONE	equ	0		; End of file received
XMOK	equ	1		; Valid data received
XMTMO	equ	2		; Timeout receiving data
XMERR	equ	3		; Checksum/protocol error
XMXTRA	equ	4		; Extraneous block resent

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
	sta	xmresp
	rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
xmread	clr	btype		; Reset block type
	ldx	#xmresp
	ldy	#1
	jsr	DWWrite
        ldx     #btype          ; Read packet
        ldy     #132
        jsr     DWRead
        beq     xcheck		; Full-length packet received
        lda     btype		; Short packet
        cmpa    #EOT            ; Is it EOT?
        beq     xfinish
	lda	#XMTMO		; Timeout
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
	lda	#XMXTRA
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
	lda	#XMOK
xout	stb	xmresp
	ldx	#bdata
	rts

snak	ldb	#NAK
	lda	#XMERR
	bra	xout

xfinish	lda	#ACK
	sta	xmresp
	ldx	#xmresp
	ldy	#1
	jsr	DWWrite
	lda	#XMDONE
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
lblk    equ	$01d1	; Cassette file name buffer
xmresp	equ	$01d2

; XMODEM packet
btype   equ	$0200	; Cassette data buffer
blk     equ	btype+1
iblk    equ	btype+2
bdata   equ	btype+3
cksum   equ	bdata+128

