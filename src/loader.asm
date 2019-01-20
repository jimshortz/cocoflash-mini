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
prnum   equ     $bdcc

; Memory locations
rstflg  equ     $71
rstvec  equ     $72
blktyp  equ     $7c
blklen  equ     $7d
cbufad  equ     $7e
csrerr  equ     $81
curpos  equ     $88
casbuf  equ     $01da

; Hardware registers
config  equ     $ff64
fcntrl  equ     config
bank_lo equ     config+1
bank_hi equ     config+2

hdrtyp  equ     3               ; Type of header block

    if  ROM
        jmp reloc,pcr
    endif

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Main routine
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
main    clr     curpos+1        ; Return to home
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
1       jsr     first_kb
2       jsr     bcheck          ; Check a 1KB block
        beq     3f              ; Skip if clean
        lda     start_bank      ; Are we in erase mode?
        bpl     abort
        jsr     erase
3       jsr     next_kb
        bne     2b
        jsr     meter

        ; Download and program chunks
        ldx     #wrmsg
        jsr     first_kb
1       jsr     read_kb         ; Read 1KB from the tape
        bne     abort
        jsr     pgmblk          ; Burn it to flash
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

        clr     hdr_end         ; Null terminate fname
        ldx     #fname          ; Print file name
        jsr     prstr

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
first_kb  
        jsr     prstr               ; Print phase
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
        ; Fall through to meter
        
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 
; Displays progress of operations
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 
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
erase   orcc    #$50    ; Disable interrupts
        lda     #$81    ; Set bits for led on and write enable
        sta     fcntrl  ; Send to flash card control register
        lbsr    preamb  ; Send erase instruction
        lda     #$80
        sta     $caaa
        lbsr    preamb
        lda     #$30
        sta     $c000
chkera  lda     $c000   ; Get a test data byte
        cmpa    #$ff    ; Is it erased?
        bne     chkera  ; No, wait
        andcc   #$af    ; Enable interrupts
        clra
        sta     fcntrl  ; Turn off write access and led
        rts

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
pgmblk  ldx         #buf
        ldy         target
        orcc       #$50   ;disable interrupts
        clrb                ; set error count = 0
loop    cmpx       #bufend ;have we finished a 1k chunk?
        beq        exit   ;yes, exit loop
        incb
        cmpb       #$ff   ;pass # 255?
        beq        fail   ;too many attempts, fail
        lda        #$81   ;set bits for led on and write enable
        sta        fcntrl ;send to flash card control register
        lbsr       preamb ; set up write sequence
        lda        #$a0
        sta        $caaa
        lda        ,x     ; get data to write to flash
        sta        ,y     ; write to flash
ppoll   lda        $c000  ; poll the operation status
        eora       $c000
        anda       #$40   ; bits toggling?
        bne        ppoll  ; yes, keep polling
        clra
        sta        fcntrl ; turns off led and disables write mode
        pshs       b
        clrb
delay   nop
        incb
        cmpb       #100
        ble        delay
        puls       b
        lda        ,y     ; load data back
        cmpa       ,x     ; does it match?
        bne        reset  ; try again
        clrb                ; clear error count
        leax       1,x    ; increment source address
        leay       1,y    ; increment destination address
        bra        loop   ; next byte
reset   lda        #$f0   ; reset command
        sta        $c000  ; send reset
ppoll2  lda        $c000  ; poll the operation status
        eora       $c000
        anda       #$40   ; bits toggling?
        bne        ppoll2 ; yes, keep polling
        bra        loop   ; go try again
exit    andcc      #$af   ; enable interrupts
        clra
        sta        fcntrl ; turn off write access and led
        rts
fail    andcc      #$af         ; enable interrupts
        clra
        sta     fcntrl          ; turn off write access and led
        sty     target          ; for debugging
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Writes common "preamble" code to ROM (for both erase and program)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
preamb  lda        #$aa
        sta        $caaa
        lda        #$55
        sta        $c555
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Prints a string to the screen
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
prstr   lda ,x+
        beq 2f
        jsr [chrout]
        bra prstr
2       rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Warm start handler
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    if  ROM
bye     nop
        clr     rstvec
        clr     bank_lo
        clr     bank_hi
        lda     #2
        sta     config
        jmp     [reset]
    endif

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Messages
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
wait    fcc 13,"RECEIVING ",0
bnkmsg  fcc 13,"BANK      ",0
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

    if  ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Copy program from ROM to RAM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
reloc   leax    main,pcr
        ldy     #main
1       lda     ,x+
        sta     ,y+
        cmpy    #reloc
        blo     1b

        lda     #$55            ; Install reset handler
        sta     rstflg
        ldx     #bye
        stx     rstvec

        jmp     main            ; Transition to RAM
    endif

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Variables
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
kb_cur          rmb     2       ; Current 1KB block being processed
target          rmb     2       ; Pointer to read/write

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

        end     main
