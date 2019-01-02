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
polcat  equ     $a000
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

hdrtyp  equ     3               ; Type of header block
ssize   equ     64              ; Size of stack to allocate

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
main    lds     #stack+ssize-1  ; Move stack to low RAM
        clr     rstflg          ; Reset button does cold start
        clr     curpos+1        ; Return to home
        ldx     #hello
mloop   jsr     prstr

mloop1  ldx     #wait
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
        beq     3f              ; Skip if clean
        lda     start_bank      ; Are we in erase mode?
        bpl     abort
        jsr     ERASE
3       jsr     next_kb
        bne     2b
        jsr     meter

        ; Download and program chunks
        ldx     #wrmsg
        jsr     reset
1       jsr     read_kb         ; Read 1KB from the tape
        bne     abort
        jsr     PGMBLK          ; Burn it to flash
        bne     abort
        jsr     next_kb
        bne     1b

        ; Print OK message and receive next file
        ldx     #succ
        bra     mloop

abort   ldx     #failmsg        ; Return FAIL unless this was a tape error
        lda     csrerr
        beq     1f
        ldx     #taperr
1       jsr     prstr
        ldx     #again
        jsr     prstr
2       jsr     [polcat]
        beq     2b
        jmp     mloop1

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Reads the header block
;
; Output:
;   Z=0 if successful
;   start_bank  = First bank to program
;   kb_cnt      = Number of KB to program
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
readhdr jsr     [csrdon]        ; Turn on the tape
        ldx     #header
        stx     cbufad
        jsr     [blkin]         ; Read header block
        lda     csrerr          ; Check for errors
        bne     1f
        lda     blktyp          ; Verify type
        cmpa    #hdrtyp
        bne     1f
       
        lda     blklen          ; Verify block length
        cmpa    #buf-header
        bne     1f

        ldx     #bnkmsg         ; Print starting bank
        jsr     prstr
        ldd     start_bank
        anda    #7              ; Mask off mode bits
        jsr     prnum

        clra
1       rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 
; Return to first bank and set target pointer
;
; Outputs:
;   Z=1 If at end, Z=0 if more blocks remain
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 
reset   jsr     prstr               ; Print phase
        ldd     start_bank          ; Reset bank pointer
        anda    #$7                 ; Remove extra bits
        sta     bank_hi
        stb     bank_lo
        ldx     #$c000              ; Reset target pointer
        stx     target
        clr     kb_cur              ; Reset KB counter
        clr     kb_cur+1
        jmp     meter

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 
; Advance bank and target pointer to next 1k block
;
; Outputs:
;   Z=1 If at end, Z=0 if more blocks remain
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 
next_kb ldx     target
        leax    1024,x          ; Move forward 1KB
        cmpx    #$d000          ; Have we reached end of ROM window?
        blo     2f
        ldx     #$c000          ; Reset to beginning of ROM window
        inc     bank_lo
        bne     2f
        inc     bank_hi
2       stx     target
        ldy     kb_cur          ; Increment kb_cur
        leay    1,y
        sty     kb_cur
        ; Fall through
        
meter   lda     curpos+1        ; Reset cursor to column 10
        anda    #$e0
        ora     #10
        sta     curpos+1
        ldd     kb_cur          ; Print out current block num
        jsr     prnum
        lda     #'/'
        jsr     [chrout]
        ldd     kb_cnt          ; Print out total kb
        jsr     prnum
        ldx     #kbmsg          ; And postfix message
        jsr     prstr
        ldy     kb_cur          ; Set Z flag if at end
        cmpy    kb_cnt
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
        lda     blktyp
        coma                    ; Keep reading until we get an EOF block
        bne     1b
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

prnum   equ $bdcc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Messages
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
wait    fcc 13,"RECEIVING",13,0
bnkmsg  fcc    "BANK      ",0
kbmsg   fcc " KB ",0
bckmsg  fcc 13,"CHECKING",0
ermsg   fcc 13,"ERASING",0
wrmsg   fcc 13,"WRITING",0
failmsg fcc 32,"FAILED",13,0
taperr  fcc 32,"TAPE ERROR",13,0
succ    fcc 13,"SUCCESS",13,0
again   fcc 13,"ANY KEY TO RETRY",0
hello   fcc "COCOFLASH MINI LOADER V0.9"
        fcc 13,"(C)2018 - JIM SHORTZ",13,0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Header block
;
; The host header block is downloaded directly here.  Make sure it
; matches struct pgm_header in rom2wav.c
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
header  
start_bank      rmb     2       ; Starting bank
kb_cnt          rmb     2       ; Number of 1KB units to download
fname           rmb     16      ; File name
hdr_end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Data buffer
;
; This must fit within available host memory
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
buf             rmb     1024
bufend          

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Variables
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    org casbuf
stack           rmb     ssize   ; Replacement stack
kb_cur          rmb     2       ; Current 1KB block being processed
target          rmb     2       ; Pointer to read/write

        end     main
