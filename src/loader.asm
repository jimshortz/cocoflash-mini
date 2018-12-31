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
csrdon  equ     $a004
blkin   equ     $a006

; Memory locations
text    equ     $0400           ; Text screen
textend equ     text+(16*32)    ; End of screen
map_start equ   text+64         ; 3rd line of screen
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

hdrlen  equ     36              ; Size of header block
hdrtyp  equ     3               ; Type of header block

; Status characters
rev     equ     $3f             ; AND to get reverse video
norm    equ     $40             ; OR to get normal video
c_unk   equ     '?' & rev       ; Not blank checked yet
c_full  equ     'X' & rev       ; Failed blank check
c_empty equ     '.' & rev       ; Passed blank check
c_read  equ     'R' & rev       ; Reading from tape
c_write equ     'W' & rev       ; Writing to rom
c_ok    equ     '*' & rev       ; Written successfully
c_fail  equ     '!' & rev       ; Failed to write
c_erase equ     'E' & rev       ; Erasing bank

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
main    lds     #casbuf+64      ; Move stack to low RAM
        clr     rstflg          ; Reset button does cold start
        jsr     clrscn

abort   jsr     read_hdr
        bne     abort

        ; Perform blank check
        jsr     reset
        jsr     draw            
1       jsr     bcheck          ; Check a 1KB block
        beq     2f              ; Skip if clean
        lda     start_bank      ; Are we in erase mode?
        bpl     abort           ; Abort if not
        jsr     ERASE
2       jsr     next_kb
        bne     1b

        ; Download and program chunks
        jsr     reset
3       jsr     read_kb         ; Read 1KB from the tape
        bne     abort
        jsr     PGMBLK          ; Burn it to flash
        bne     abort
        jsr     next_kb
        bne     3b
        bra     abort

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 
; Clears the screen and homes the cursor
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
clrscn  ldx     #text
        stx     curpos
        lda     #$60
1       sta     ,x+
        cmpx    #textend
        blo     1b
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Reads the header block
;
; Output:
;   Z=0 if successful
;   start_bank  = First bank to program
;   kb_cnt      = Number of KB to program
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
read_hdr
        ldx     #map_start      ; Turn the gauge to normal background
1       lda     ,x
        ora     #norm
        sta     ,x+
        cmpx    #textend
        blo     1b
2       jsr     [csrdon]        ; Turn on the tape
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

        ldd     buf+32          ; Extract start_bank and kb_cnt
        std     start_bank
        ldd     buf+34
        std     kb_cnt

        clra                    ; Return OK
1       rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Draws the progress map on the screen
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
draw
        jsr     clrscn
        ldx     #buf            ; Copy banner to top line
        ldy     #text
1       lda     ,x+
        anda    #rev            ; Set normal background
        ora     #norm
        sta     ,y+
        cmpx    #buf+32
        blo     1b

        ldx     kb_cnt          ; Fill with unknowns
        ldy     #map_start
        sty     curpos
        lda     #c_unk
2       sta     ,y+
        leax    -1,x
        bne     2b
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 
; Return to first bank and set target pointer
;
; On exit, X=target location, Y = number of KB remianing, Z=at end
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 
reset   ldx     #map_start          ; Reset cursor to beginning of map
        stx     curpos
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
next_kb inc     curpos+1        ; Advance cursor one character
        bcc     1f
        inc     curpos
1       ldx     target
        leax    1024,x          ; Move forward 1KB
        cmpx    #$d000          ; Have we reached end of ROM window?
        blo     2f
        ldx     #$c000          ; Reset to beginning of ROM window
        inc     bank_lo         ; And move to the next bank
        bcc     2f
        inc     bank_hi
2       stx     target
        ldy     kb_rem          ; Decrement kb_rem
        leay    -1,y
        sty     kb_rem
        cmpy    #0
        rts
        
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Blank check current 1KB block
;
; Outputs: Z=0 if blank
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
bcheck  ldb     #c_full         ; Park "bad" status in B register
        ldx     target          ; Iterate from target to target+1KB
        ldy     #1024
1       lda     ,x+
        coma                    ; Make sure it is $ff
        bne     2f
        leay    -1,y
        bne     1b
        ldb     #c_empty        ; Successful - use "good" status`
        clra                    ; Return OK
2       stb     [curpos]        ; Write status to screen
        cmpa    #0              ; Reload Z register
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Erase bank
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
ERASE   LDB     #c_erase
        STA     [curpos]
        ORCC    #$50    ; Disable interrupts
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
read_kb ldb     #c_read         ; Update status display to 'reading'
        stb     [curpos]
        ldx     #buf            ; Reset cassette buffer to buf
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
PGMBLK  LDB     #c_write
        STB     [curpos]
        LDX         #buf
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
        LDB         #c_ok
        STB     [curpos]
        CLRA
        STA        FCNTRL ; Turn off write access and LED
        RTS
;FAIL    STA        $FFDF       ; Disable ROM in memory map
FAIL    ANDCC      #$AF         ; Enable interrupts
        CLRA
        STA     FCNTRL          ; Turn off write access and LED
        STY     target          ; For debugging
        LDA     #c_fail         ; Also causes Z=0 (error)
        STA     [curpos]
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
; Variables
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    org casbuf+66
start_bank      rmb     2       ; Starting bank
kb_cnt          rmb     2       ; Number of 1KB units to download
kb_rem          rmb     2       ; Number of 1KB units remaining in current pass
target          rmb     2       ; Pointer to read/write

buf             equ     $800
bufend          equ     buf+1024
        end     main
