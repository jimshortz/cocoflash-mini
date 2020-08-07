romst   equ     $c000

; Hardware registers
;config  equ     $ff64
;fcntrl  equ     config
;bank_lo equ     config+1
;bank_hi equ     config+2

; XMODEM constants
SOH     equ     $1
ACK     equ     $6
EOT     equ     $4
NAK     equ     $15


xmodem  lda     #$01
        sta     bank_hi
        lda     #$01
        sta     bank_lo

        ; XMODEM download
        ldx     #romst
        stx     target
        clra                    ; Reset block number
        sta     lblk
snak    clra                    ; Reset packet type
        sta     btype
        lda     #NAK            ; Send a NAK
        bsr     putc
1       ldx     #btype          ; Read packet
        ldy     #132
        jsr     DWRead
        beq     2f
        lda     btype
        cmpa    #EOT            ; Is it EOT?
        beq     done
        swi                     ; Short packet
        bra     snak
2       lda     btype
        cmpa    #SOH            ; Is it SOH?
        beq     3f
        swi
        bra     snak
3       lda     blk             ; Test block number
        adda    iblk
        coma
        beq     4f
        swi                     ; Bad block number
4       lda     blk
        suba    lblk
        beq     sack            ; Resend of previous block - ignore
        deca
        beq     5f
        swi                     ; Block out of sequence
        bra     snak
5       tfr     y,d             ; B=checksum of all 132 bytes
                                ; SOT+blk+blki = 0 always
        subb    cksum           ; So we just need to subtract the checksum
        cmpb    cksum           ; And compare to itself again
        beq     6f
        swi                     ; Checksum error
        bra     snak
6       inc     lblk
        swi
        jsr     pgmblk          ; Program the packet
        swi                     ; DEBUG
        bne     snak
sack    lda     #ACK            ; Send ACK and read next packet
        bsr     putc
        bra     1b

done    lda     #ACK
        ; Fall through

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Write A character to serial port
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
putc    sta     $6
        ldx     #6
        ldy     #1
        jmp     DWWrite

        include     "serio.asm"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Writes packet of data from target -> ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
pgmblk  ldx         #bdata
        ldy         target
        ;orcc        #$50    ;disable interrupts
        clrb                ; set error count = 0
loop    cmpx        #cksum  ;have we finished a chunk?
        beq         exit    ;yes, exit loop
        incb
        cmpb        #$ff    ;pass # 255?
        beq         fail    ;too many attempts, fail
        lda         #$81    ;set bits for led on and write enable
        sta         fcntrl  ;send to flash card control register
        lbsr        preamb  ; set up write sequence
        lda         #$a0
        sta         $caaa
        lda         ,x      ; get data to write to flash
        sta         ,y      ; write to flash
ppoll   lda         $c000   ; poll the operation status
        eora        $c000
        anda        #$40    ; bits toggling?
        bne         ppoll   ; yes, keep polling
        clra
        sta         fcntrl  ; turns off led and disables write mode
        pshs        b
        clrb
delay   nop
        incb
        cmpb        #100
        ble         delay
        puls        b
        lda         ,y      ; load data back
        cmpa        ,x      ; does it match?
        bne         reset   ; try again
        clrb                ; clear error count
        leax        1,x     ; increment source address
        leay        1,y     ; increment destination address
        bra         loop    ; next byte

reset   lda         #$f0    ; reset command
        sta         $c000   ; send reset
ppoll2  lda         $c000   ; poll the operation status
        eora        $c000
        anda        #$40    ; bits toggling?
        bne         ppoll2  ; yes, keep polling
        bra         loop    ; go try again

exit    ;andcc       #$af    ; enable interrupts
        sta         fcntrl  ; turn off write access and led
        sty         target
        clra
        rts

fail    ;andcc       #$af    ; enable interrupts
        sta         fcntrl  ; turn off write access and led
        sty         target
        lda         #$ff    ; Return non-zero
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Writes common "preamble" code to ROM (for both erase and program)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;preamb  lda        #$aa
;        sta        $caaa
;        lda        #$55
;        sta        $c555
;        rts

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

