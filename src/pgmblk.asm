src_end	equ	$16

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Writes 1KB of data from target -> ROM
; X = source
; Y = target
; D = byte count
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
pgmblk  std	src_end	; Compute end address
	tfr	x,d
	addd	src_end
	std	src_end
	clrb		; set error count = 0
ploop  	cmpx	src_end	;have we finished a 1k chunk?
        beq     pexit	;yes, exit loop
        incb
        cmpb    #$ff	;pass # 255?
        beq     fail	;too many attempts, fail
        lda     #$81	;set bits for led on and write enable
        sta     fcntrl	;send to flash card control register
        lbsr    preamb	; set up write sequence
        lda     #$a0
        sta     $caaa
        lda     ,x	; get data to write to flash
        sta     ,y	; write to flash
ppoll   lda     $c000	; poll the operation status
        eora    $c000
        anda    #$40   	; bits toggling?
        bne     ppoll  	; yes, keep polling
        clra
        sta     fcntrl 	; turns off led and disables write mode
        pshs    b
        clrb
delay   nop
        incb
        cmpb    #100
        ble     delay
        puls    b
        lda     ,y     	; load data back
        cmpa    ,x     	; does it match?
        bne     pgrst  	; try again
        clrb    	; clear error count
        leax    1,x    	; increment source address
        leay    1,y    	; increment destination address
        bra     ploop   	; next byte
pgrst   lda     #$f0   	; reset command
        sta     $c000  	; send reset
ppoll2  lda     $c000  	; poll the operation status
        eora    $c000
        anda    #$40   	; bits toggling?
        bne     ppoll2 	; yes, keep polling
        bra     ploop   	; go try again
pexit   clra
        sta	fcntrl 	; turn off write access and led
        rts
fail    clra
        sta	fcntrl	; turn off write access and led
	ldx	#$ff
        rts

