;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; loader.asm
;
; Downloads ROM code from a PC via the cassette port as prepared by
; rom2wav.c. Writes ROM code into the CocoFlash card.  Downloads and
; programs in 1KB chunks.
;
; rom2wav.c includes a header block that specifies the target bank,
; length, and whether or not erasure is required.  This program performs
; blank checks (to ensure ROM has not already been written) and
; optionally erases dirty banks.
;
; Screen I/O is kept minimal to conserve memory.  This loader only
; requires 512 bytes of RAM and can run in a 4K Coco 1.
;
;-----------------------------------------------------------------------
; Author:       Jim Shortz
; Date:         Dec 29, 2018
;
; Target:       Radio Shack Color Computer
; Assembler:    asm6809 cross assembler
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        org     $600
        setdp   0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; CoCo ROM entry vectors
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
chrout  equ     $a002
csrdon  equ     $a004
blkin   equ     $a006

; Memory locations
rstflg  equ     $71
blktyp  equ     $7c
blklen  equ     $7d
cbufad  equ     $7e
csrerr  equ     $81
curpos  equ     $88
casbuf  equ     $01da

; Hardware registers
config  equ     $ff64
bank_lo equ     config+1
bank_hi equ     config+2
FCNTRL  equ     config
rom_en  equ     $ffde 
ram_en  equ     $ffdf
mpak    equ     $ff7f
;reset   equ     $fffe
pia1    equ     $ff21
motor   equ     $08             ; Tape motor control bit (PIA1)

hdrlen  equ     48              ; Size of header block
hdrtyp  equ     3               ; Type of header block
ssize   equ     64              ; Size of stack to allocate

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; NOTE - main is at the bottom so its space can be reused
mloop   jsr     prstr
        ldx     #wait
        jsr     prstr
1       jsr     readhdr
        bne     1b              ; Silently retry to avoid noisy condition
                                ; after a blank check fails but the PC
                                ; keeps sending.

        ; Perform blank check/erase
        ldx     #bckmsg
        lda     start_bank      ; Are we in erase mode?
        bpl     1f
        ldx     #ermsg          ; Change message if so
1       jsr     reset
2       jsr     bcheck          ; Check a 1KB block
        beq     4f              ; Skip if clean
        lda     start_bank      ; Are we in erase mode?
        bmi     3f              ; If yes, attempt erase
        ldx     #blkerr         ; Error if not
        bpl     mloop 
3       jsr     ERASE
4       jsr     next_kb
        bne     2b

        ; Download and program chunks
        ldx     #wrmsg
        jsr     reset
1       jsr     read_kb         ; Read 1KB from the tape
        beq     2f
        ldx     #taperr
        bra     mloop
2       jsr     PGMBLK          ; Burn it to flash
        beq     3f
        ldx     #wrterr
        bra     mloop
3       jsr     next_kb
        bne     1b
        ldx     #succ
        bra     mloop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Reads the header block
;
; Output:
;   Z=0 if successful
;   start_bank  = First bank to program
;   kb_cnt      = Number of KB to program
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
readhdr jsr     [csrdon]        ; Turn on the tape
        ldx     #buf
        stx     cbufad
        jsr     [blkin]         ; Read header block
        lda     csrerr          ; Check for errors
        bne     1f
        lda     blktyp          ; Verify type
        cmpa    #hdrtyp
        bne     1f
       
        lda     blklen          ; Verify block length
        cmpa    #hdrlen
        bne     1f

        ldd     buf             ; Extract start_bank and kb_cnt
        std     start_bank

        ldd     buf+2
        std     kb_cnt

        ldx     #buf+4          ; Print banner
        jsr     prstr

        clra                    ; Return OK
1       rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 
; Return to first bank and set target pointer
;
; On exit, X=target location, Y = number of KB remianing, Z=at end
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 
reset   jsr     prstr
        ldd     start_bank          ; Reset bank pointer
        anda    #$7                 ; Remove extra bits
        sta     bank_hi
        stb     bank_lo
        ldx     #$c000              ; Reset target pointer
        stx     target
        ldy     kb_cnt              ; Reset block counter
        sty     kb_rem
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 
; Advance bank and target pointer to next 1k block
;
; On exit, X=target location, Y = number of KB remaining, Z=at end
;
next_kb lda     #'.'
        jsr     [chrout]
        ldx     target
        leax    1024,x          ; Move forward 1KB
        cmpx    #$d000          ; Have we reached end of ROM window?
        blo     2f
        ldx     #$c000          ; Reset to beginning of ROM window
        inc     bank_lo
        bne     2f
        inc     bank_hi
2       stx     target
        ldy     kb_rem          ; Decrement kb_rem
        leay    -1,y
        sty     kb_rem
        rts
        
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Blank check current 1KB block
;
; Outputs: Z=0 if blank
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
bcheck  ldx     target          ; Iterate from target to target+1KB
        ldy     #1024
1       lda     ,x+
        coma                    ; Make sure it is $ff
        bne     2f
        leay    -1,y
        bne     1b
2       rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Erase bank
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
ERASE   ORCC    #$50    ; Disable interrupts
        ;STA    $FFDE   ; Enable ROM in memory map
        LDA     #$81    ; Set bits for LED on and write enable
        STA     FCNTRL  ; Send to flash card control register
        LBSR    PREAMB  ; Send erase instruction
        LDA     #$80
        STA     $CAAA
        LBSR    PREAMB
        LDA     #$30
        STA     $C000
CHKERA  LDA     $C000   ; Get a test data byte
        CMPA    #$FF    ; Is it erased?
        BNE     CHKERA  ; No, wait
        ;STA    $FFDF   ; Disable ROM in memory map
        ANDCC   #$AF    ; Enable interrupts
        CLRA
        STA     FCNTRL  ; Turn off write access and LED
        RTS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Reads a 1KB chunk from the tape
;
; Outputs:
;   buf - Contents of chunk
;   Z=0 - No error
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
read_kb ldx     #buf            ; Reset cassette buffer to buf
        stx     cbufad
1       jsr     [blkin]
        bne     2f              ; Did an error occur?
        stx     cbufad          ; Advance to next block
        lda     blklen
        cmpa    #255            ; Keep reading until we get a partial
        beq     1b
        clra                    ; Return OK
2       rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Writes 1KB of data from target -> ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
PGMBLK  LDX         #buf
        LDY         target
        ORCC       #$50   ;Disable interrupts
;        STA        $FFDE  ;Enable ROM in memory map
        CLRB                ; Set error count = 0
LOOP    CMPX       #bufend ;Have we finished a 1K chunk?
        BEQ        EXIT   ;Yes, exit loop
        INCB
        CMPB       #$FF   ;Pass # 255?
        BEQ        FAIL   ;Too many attempts, fail
        LDA        #$81   ;Set bits for LED on and write enable
        STA        FCNTRL ;Send to flash card control register
        LBSR       PREAMB ; Set up write sequence
        LDA        #$A0
        STA        $CAAA
        LDA        ,X     ; Get data to write to flash
        STA        ,Y     ; Write to flash
PPOLL   LDA        $C000  ; Poll the operation status
        EORA       $C000
        ANDA       #$40   ; Bits toggling?
        BNE        PPOLL  ; Yes, keep polling
        CLRA
        STA        FCNTRL ; Turns off LED and disables write mode
        PSHS       B
        CLRB
DELAY   NOP
        INCB
        CMPB       #100
        BLE        DELAY
        PULS       B
        LDA        ,Y     ; Load data back
        CMPA       ,X     ; Does it match?
        BNE        RESET  ; Try again
        CLRB                ; Clear error count
        LEAX       1,X    ; Increment source address
        LEAY       1,Y    ; Increment destination address
        BRA        LOOP   ; Next byte
RESET   LDA        #$F0   ; Reset command
        STA        $C000  ; Send reset
PPOLL2  LDA        $C000  ; Poll the operation status
        EORA       $C000
        ANDA       #$40   ; Bits toggling?
        BNE        PPOLL2 ; Yes, keep polling
        BRA        LOOP   ; Go try again
;EXIT   STA        $FFDF  ; Disable ROM in memory map
EXIT    ANDCC      #$AF   ; Enable interrupts
        CLRA
        STA        FCNTRL ; Turn off write access and LED
        RTS
;FAIL    STA        $FFDF       ; Disable ROM in memory map
FAIL    ANDCC      #$AF         ; Enable interrupts
        CLRA
        STA     FCNTRL          ; Turn off write access and LED
        STY     target          ; For debugging
        RTS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Writes common "preamble" code to ROM (for both erase and program)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
PREAMB  LDA        #$AA
        STA        $CAAA
        LDA        #$55
        STA        $C555
        RTS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
prstr   lda ,x+
        beq 2f
        jsr [chrout]
        bra prstr
2       rts

; Everything below this point is only used at startup
; and can safely overlap with buf

main    lds     #stack+ssize-1  ; Move stack to low RAM
        clr     rstflg          ; Reset button does cold start
        ldx     #reloc_s        ; Relocate messages into casbuf
        ldy     #reloc_t
1       lda     ,x+
        sta     ,y+
        cmpx    #reloc_e
        bne     1b
        clr     curpos+1        ; Return to home
        ldx     #hello
        lbra    mloop           ; Enter the main loop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Messages
;
; Everything in this block gets relocated into casbuf
; to make room for the transfer buffer.  Hence the weird label
; stuff
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
reloc_s
wait    equ * + reloc_t - reloc_s
        fcc 13,"RECEIVING",13,0

bckmsg  equ * + reloc_t - reloc_s
        fcc 13,"CHECKING ",0

ermsg   equ * + reloc_t - reloc_s
        fcc 13,"ERASING  ",0

wrmsg   equ * + reloc_t - reloc_s
        fcc 13,"WRITING  ",0

taperr  equ * + reloc_t - reloc_s
        fcc 13,"tape err",13,0

blkerr  equ * + reloc_t - reloc_s
        fcc 13,"not blank",13,0

wrterr  equ * + reloc_t - reloc_s
        fcc 13,"pgm err",13,0

succ    equ * + reloc_t - reloc_s
        fcc 13,"SUCCESS",13,0
reloc_e

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
hello   fcc "COCOFLASH MINI LOADER V0.9"
        fcc 13,"(C)2018 - JIM SHORTZ",13,0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Variables
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    org casbuf
reloc_t         rmb     reloc_e-reloc_s ; Relocated message strings
stack           rmb     ssize   ; Relocated stack
start_bank      rmb     2       ; Starting bank
kb_cnt          rmb     2       ; Number of 1KB units to download
kb_rem          rmb     2       ; Number of 1KB units remaining in current pass
target          rmb     2       ; Pointer to read/write

buf             equ     $800
bufend          equ     buf+1024
        end     main
