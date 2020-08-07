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
xmodem  orcc	#$50
	ldd	#$0001
        sta     bank_hi
        stb     bank_lo

        ; XMODEM download
        ldx     #romst
        stx     target
        clra                    ; Reset block number
        sta     lblk
snak    clra                    ; Reset packet type
        sta     btype
        lda     #NAK            ; Send a NAK
        jsr     putc
1       ldx     #btype          ; Read packet
        ldy     #132
        jsr     DWRead
        beq     2f
        lda     btype		; Short packet
        cmpa    #EOT            ; Is it EOT?
        beq     done
        bra     snak
2       lda     btype
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
sack    lda     #ACK            ; Send ACK and read next packet
        bsr     putc
        bra     1b

done    lda     #ACK		; Send final ack
	bsr	putc
	andcc 	#$af		; Enable interrupts
	rts

pgmerr	swi
	bra	cancel

bchkerr	swi
	bra	cancel

cancel	ldx	#cans
	ldy	#10
	jsr	DWWrite
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
	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Write A character to serial port
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
putc    sta     $6
        ldx     #6
        ldy     #1
        jmp     DWWrite

        include "serio.asm"
;	include	"pgmblk.asm"
pgmblk	swi
	leay	128,y
	clra
	rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Resources
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

