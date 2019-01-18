;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; CocoFlash ROM Mapper
;
;-----------------------------------------------------------------------
;
; Author:       Jim Shortz
; Date:         January 12, 2019
;
; Target:       Radio Shack Color Computer
; Assembler:    asm6809 cross assembler
;
;-----------------------------------------------------------------------
; This program is used to view and manage ROM banks for a CocoFlash
; card.  It runs on any CoCo and requires 2KB of RAM.
;
; The program has 5 distinct modes:
;  Map -    Shows a map of ROM banks and free/used status.
;  Hex -    Shows contents of a bank in hex.
;  ASCII -  Shows contents of a bank in ASCII.
;  Erase -  Erases a sector
;
; Routines for each mode are prefixed with a single character
; (m, h, a, e) to indicate the mode.  A mode is entered by calling
; its *mode routine.
;
; The main loop of the program is a keyboard dispatcher that calls
; subroutines listed in a mode-specific key table.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        org     $800
        setdp   0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; CoCo ROM entry vectors
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
polcat  equ     $a000
chrout  equ     $a002
csrdon  equ     $a004
blkin   equ     $a006
blkout  equ     $a008
joyin   equ     $a00a
wrtldr  equ     $a00c

; Hardware registers
config  equ     $ff64
bank_lo equ     config+1
bank_hi equ     config+2
fcntrl  equ     config
rom_en  equ     $ffde 
ram_en  equ     $ffdf
mpak    equ     $ff7f
reset   equ     $fffe

; Memory locations
cbufad  equ     $7e
blktyp  equ     $7c
blklen  equ     $7d
text    equ     $0400           ; Text screen
textend equ     text+16*32
rom     equ     $c000
romend  equ     $d000

; Key codes
kdown   equ     $0a
kup     equ     $5e
kleft   equ     $08
kright  equ     $09
kent    equ     $0d

prime   equ     139             ; Sampling interval for blank check

    if  ROM
        jmp     reloc,pcr
    endif

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Entry point
; Clears to bank 0 and enters map mode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
main    clr     bank_lo
        clr     bank_hi
        jsr     mmode
1       jsr     [polcat]        ; Read keyboard and dispatch
        beq     1b
        ldx     keymap
2       cmpa    ,x+
        bne     3f              ; Not a match
        ldx     ,x              ; Get target address
        jsr     ,x              ; JSR to it
        bra     1b

3       leax    2,x             ; Next entry
        ldb     ,x
        bne     2b
        bra     3b

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Enters map mode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
mmode   ldd     #mkeys          ; Assign keymap
        std     keymap
        jsr     clrscn          ; Clear screen
        ldx     #mmenu          ; Draw static text
        jsr     draw
        clr     addr            ; Reset addr to 0 for next time 
        clr     addr+1          ; hex or ascii mode is entered
        ; Fall through to mdraw

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Map mode draw routine
;
; Draws free/busy map on left half of the screen.  256 banks.
; Starts at $07FC because this is the first physical bank of the
; ROM and is the boundary used during erasure.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
mdraw   jsr     drawbnk         ; Draw bank number
        jsr     drawmap         ; Call helper
        jmp     mxorsel         ; Highlight it

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Core map drawing routine used by both map and erase mode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
drawmap lda     bank_hi         ; Save selected bank
        ldb     bank_lo
        pshs    d
        cmpb    #$fc            ; Compute starting bank of screen
        bhs     1f              ; All but the 1st 4 banks are
        deca                    ; on the previous page
1       sta     page
        ldb     #$fc
        sta     bank_hi         ; Move to 1st bank in page
        stb     bank_lo
        ldy     #text
2       ldb     #'-'|$40        ; Empty bank symbol
        jsr     is_free
        beq     3f
        ldb     #'X'            ; Change to full bank
3       stb     ,y+             ; Draw it
        inc     bank_lo         ; Advance to next bank
        bne     4f
        inc     bank_hi
4       tfr     y,d
        andb    #$f             ; Have we reached the 16th bank?
        bne     2b
        leay    16,y            ; Move to the next line
        cmpy    #textend
        blo     2b
        puls    d               ; Restore selected bank
        sta     bank_hi
        stb     bank_lo
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Map mode navigation routines
; These choose an offset to apply and call mnav to do the work.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

mprev   ldd     #-256
        bra     mnav

mnext   ldd     #256
        bra     mnav

mleft   ldd     #-1
        bra     mnav

mright  ldd     #1
        bra     mnav

mup     ldd     #-16
        bra     mnav

mdown   ldd     #16
        bra     mnav

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Map mode central navigation routine.
;
; Inputs:
;   D - Offset to apply
;   bank_lo, bank_hi - Currently selected bank
; Outputs:
;   bank_lo, bank_hi - Newly selected bank
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
mnav    pshs    d
        jsr     mxorsel         ; Clear existing selection
        puls    d
        addb    bank_lo         ; Adjust selected bank
        adca    bank_hi
        sta     bank_hi
        stb     bank_lo
        jsr     mxorsel         ; Attempt to update selection
        lbne    mdraw           ; Went off page - redraw
        lbra    drawbnk         ; Update bank number
        
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Map mode select/deselect routine
;
; Inputs:
;   bank_lo, bank_hi - Bank to select
; Outputs:
;   Z = 0   Bank selected
;   Z = 1   Selected bank off screen
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
mxorsel leas    -2,s
        lda     bank_hi         ; Compute relative bank #
        ldb     bank_lo
        subb    #$fc
        sbca    page
        anda    #7              ; Wrap around
        bne     1f              ; If relative bank >= $100 - bail
        stb     0,s
        andb    #$0f            ; column
        stb     -1,s
        ldb     0,s
        andb    #$f0            ; row*16
        lslb                    ; row*32
        rola
        orb     -1,s            ; +column
        ldx     #text
        leax    d,x
        lda     ,x
        eora    #$40            ; XOR background bits at screen address
        sta     ,x
        clra                    ; return OK
1       leas    2,s
        rts


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Hex mode entry routine
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
hmode   ldd     #hkeys
        std     keymap
        jsr     clrscn
        ldx     #hmenu          ; Draw menu
        jsr     draw
        ; Fall through to hdraw

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Hex mode draw routine
;
; Draws 128 bytes of hex on the left 2/3 of the screen
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
hdraw   jsr     drawbnk         ; Draw bank #
        jsr     drawadr         ; Draw address
        ldx     addr            ; Draw hex bytes
        leax    rom,x
        ldy     #text
1       lda     ,x+
        jsr     drawbyt
        leay    1,y             ; Space
        tfr     x,d             ; Have we reached the 8th byte?
        andb    #7              
        bne     1b
        leay    8,y             ; Move to next line
        cmpy    #textend
        blo     1b
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Hex mode navigation routines
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
hnext   ldd     #128
        jsr     hnav
        lbra    hdraw
                      
hprev   ldd     #-128
        jsr     hnav
        lbra    hdraw

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;                      
; Hex mode central navigation routine
;
; Inputs:
;   bank_lo, bank_hi - Current bank
;   addr - Current address within bank
;   D - offset to apply
;
; Outputs:
;   bank_lo, bank_hi - New bank to view
;   addr - New address within bank
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;                      
hnav    addd    addr
        std     addr
        bpl     1f
        lda     #$0f        ; Underflowed - decrement bank
        sta     addr
        ldd     #-1
        bra     2f
                      
1       cmpa    #$10
        blo     3f
        clr     addr         ; Overflowed - increment bank
        ldd     #1
2       addb    bank_lo
        adca    bank_hi
        sta     bank_hi
        stb     bank_lo
3       rts
                      
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Enters ASCII mode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
amode   ldd     #akeys
        std     keymap
        jsr     clrscn
        ldx     #amenu      ; Draw menu
        jsr     draw
        clr     addr+1      ; Always view on 256 byte boundaries
        ; Fall through to adraw

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; ASCII mode draw routine
;
; Draws 256 bytes of chars on the left 1/2 of the screen
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
adraw   jsr     drawbnk
        jsr     drawadr
        ldx     addr            ; Draw ascii bytes
        leax    rom,x
        ldy     #text
1       lda     ,x+
        sta     ,y+
        tfr     x,d             ; Have we reached the 16th byte?
        andb    #$f              
        bne     1b
        leay    16,y            ; Move to next line
        cmpy    #textend
        blo     1b
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; ASCII mode navigaton routines
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
anext   ldd     #256
        jsr     hnav
        lbra    adraw
                      
aprev   ldd     #-256
        jsr     hnav
        lbra    adraw

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Erase mode entry routine
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
emode   ldx     #ekeys
        stx     keymap
        jsr     clrscn
        jsr     drawmap     ; Redraw bank map
        ldx     #emenu      ; Draw static text
        jsr     draw
        jsr     ebound      ; Compute bounds of erasure
        jsr     drawbnk     ; Draw starting bank #
1       pshs    x           ; Highlight banks to erase
        jsr     mxorsel
        puls    x
        leax    -1,x
        beq     2f
        inc     bank_lo
        bne     1b
        inc     bank_hi
        bra     1b
2       jsr     drawbnk2    ; Draw ending bank #
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Does the actual erase and switches back to map mode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
doerase jsr     erase
        lbra    mmode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Computes boundary of bank erasure
;
; Since the flash chip can only erase by sector, this routine computes
; the full effect of erasing a bank.  The first 16 sectors are 8K
; (2 banks/sector) the remaining ones are 64K (16 banks/sector)
;
; Inputs:
;   bank_lo, bank_hi - Bank to erase
;
; Outputs:
;   bank_lo, bank_hi - First bank to erase
;   X - number of banks to erase
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
ebound  lda     bank_hi
        ldb     bank_lo
        addd    #4              ; Convert to physical bank
        anda    #7              ; handle wraparound
        andb    #~1             ; Snap to 2 bank boundary
        ldx     #2              ; Erase 2 banks
        cmpd    #16             ; Only first 16 use 2 banks/sector
        blo     1f
        andb    #~15            ; Snap to 16 bank boundary
        ldx     #16             ; Erase 16 banks
1       subd    #4              ; Back to logical bank
        anda    #7              ; handle wraparound
        sta     bank_hi         ; move to starting bank
        stb     bank_lo
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;        
; Common routines
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;        

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Leaves the program
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    if  ROM
exit    clr     bank_lo         ; Switch back to bank 0
        clr     bank_hi
        lda     #2              ; And auto-start
        sta     fcntrl
        jmp     [reset]
    else
exit    jsr     clrscn
        leas    2,s             ; Unwind the stack
        rts
    endif
        
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Test emptiness of bank.
;
; NOTE - Doesn't check every location.  Use a smaller version of
; prime to get more fidelty (at the expense of slower draw times)
;
; Inputs
;   bank_lo, bank_hi - Bank to check
; Output
;  Z - set if bank is empty
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
is_free
        ldx     #rom
1       lda     ,x
        coma
        bne     2f
        leax    prime,x         ; Sample the bank using a prime
        cmpx    #romend
        blo     1b
        clra
2       rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Clears the screen
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
clrscn  
        ldx     #text
        lda     #$60
1       sta     ,x+
        cmpx    #textend
        bne     1b
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Draws static text
; X - pointer to text block (as established by stext macro)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
draw    ldy     ,x++
        cmpy    #$ffff          ; Reached the end?
        beq     2f
        leay    text,y
1       lda     ,x+
        beq     draw
        ora     #$40
        sta     ,y+
        bra     1b
2       rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Draw bank number on the screen
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
drawbnk ldy     #bnkpos
        lda     bank_hi
        ldb     bank_lo
        jmp     drawwrd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Draw ending bank number on the screen (erase mode)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
drawbnk2 ldy     #bnkpos2
        lda     bank_hi
        ldb     bank_lo
        jmp     drawwrd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Draw address on screen (hex, ascii modes)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
drawadr ldy     #addrpos
        ldd     addr
        jmp     drawwrd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Draw a word (2 bytes) on the screen in hex
;
; Inputs:
;   D - Word to draw
;   Y - Location to draw to
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
drawwrd bsr     drawbyt
        exg     a,b
        ; Fall through to drawbyt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Draw a byte on the screen in hex
;
; Inputs:
;   A - Byte to draw
;   Y - Location to draw to
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
drawbyt pshs    a
        lsra
        lsra
        lsra
        lsra
        bsr     drawnyb
        puls    a
        ; Fall through to drawnyb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Draw a nybble on the screen in hex
;
; Inputs:
;   A - Nybble to draw (lo)
;   Y - Location to draw to
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
drawnyb anda    #$0f
        cmpa    #10
        bge     1f
        adda    #$70
        bra     2f
1       adda    #'A'-10
2       sta     ,y+
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Erase ROM bank
;
; Inputs
;   bank_lo, bank_hi - Bank to erase
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
erase   pshs    cc
        orcc    #$50    ; Disable interrupts
        ;sta    $ffde   ; Enable rom in memory map
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
        ;sta    $ffdf   ; Disable rom in memory map
        puls    cc      ; Restore interrupt status
        clra
        sta     fcntrl  ; Turn off write access and led
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Write AA 55 to ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
preamb  lda        #$aa
        sta        $caaa
        lda        #$55
        sta        $c555
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Tables
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Defines a keymap entry
kmap    macro
        fcb     \1
        fdb     \2
        endm
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Mappings for map mode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
mkeys   kmap    'P',    mprev 
        kmap    'N',    mnext
        kmap    kleft,  mleft
        kmap    kright, mright
        kmap    kup,    mup
        kmap    kdown,  mdown
        kmap    'H',    hmode
        kmap    'A',    amode
        kmap    'E',    emode
        kmap    'X',    exit
        fcb     0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Mappings for hex mode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
hkeys   kmap    'P',    hprev 
        kmap    kleft,  hprev
        kmap    'N',    hnext
        kmap    kright, hnext
        kmap    'M',    mmode
        kmap    'A',    amode
        kmap    'X',    exit
        fcb     0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Mappings for ascii mode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
akeys   kmap    'P',    aprev 
        kmap    kleft,  aprev
        kmap    'N',    anext
        kmap    kright, anext
        kmap    'M',    mmode
        kmap    'H',    hmode
        kmap    'X',    exit
        fcb     0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Mappings for erase mode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
ekeys   kmap    'N',    mmode 
        kmap    'Y',    doerase
        fcb     0

; Defines static text (row, column, text)
stext   macro
        fdb     \1*32+\2
        fcn     \3
        endm

mmenu
        stext   0,24,   "BANK"
        stext   6,24,   "(E)RASE"
        stext   7,24,   "(H)EX"
        stext   8,24,   "(A)SCII"
        stext   9,24,   "(N)EXT"
        stext   10,24,  "(P)REV"
        stext   11,24,  "E(X)IT"
        stext   14,19,  "COCOMAP 0.9"
        stext   15,18,  "BY JIM SHORTZ"
        fdb     $ffff

; Screen positions for dynamic text
bnkpos  equ     text+32*1+24
bnkpos2 equ     text+32*3+24
addrpos equ     text+32*4+24

hmenu
        stext   0,24,   "BANK"
        stext   3,24,   "ADDR"
        stext   6,24,   "(E)RASE"
        stext   7,24,   "(M)AP"
        stext   8,24,   "(A)SCII"
        stext   9,24,   "(N)EXT"
        stext   10,24,  "(P)REV"
        stext   11,24,  "E(X)IT"
        fdb     $ffff

amenu
        stext   0,26,   "BANK"
        stext   3,26,   "ADDR"
        stext   6,24,   "(E)RASE"
        stext   7,24,   "(M)AP"
        stext   8,24,   "(H)EX"
        stext   9,24,   "(N)EXT"
        stext   10,24,  "(P)REV"
        stext   11,24,  "E(X)IT"
        fdb     $ffff

emenu
        stext   0,24,   "BANK"
        stext   2,24,   " TO"
        stext   6,22,   "ERASE ALL"
        stext   7,22,   "SELECTED"
        stext   8,22,   "BANKS?"
        stext   10,22,  "(Y)ES"
        stext   11,22,  "(N)O"
        fdb     $ffff

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Global variables
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
page    rmb     1       ; First bank displayed on map (hi byte only)
addr    rmb     2       ; Address within bank to show (hex, ascii mode)
keymap  rmb     2       ; Active key mapping table


    if  ROM

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Relocate to RAM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
reloc   leax    main,pcr
        ldy     #main
1       lda     ,x+
        sta     ,y+
        cmpy    #reloc
        blo     1b
        jmp     main
    endif

        end     main
