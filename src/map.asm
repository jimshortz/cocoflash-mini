;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; CocoFlash programming software
;
;-----------------------------------------------------------------------
;
; Author:       Jim Shortz
; Date:         June 29, 2017
;
; Target:       Radio Shack Color Computer
; Assembler:    asm6809 cross assembler
;
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

cbufad  equ     $7e
blktyp  equ     $7c
blklen  equ     $7d

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
text    equ     $0400           ; Text screen
textend equ     text+16*32
rom     equ     $c000

; Key codes
kdown   equ     $0a
kup     equ     $5e
kleft   equ     $08
kright  equ     $09
kent    equ     $0d

main    clr     bank_lo
        clr     bank_hi
        jsr     map
loop    jsr     [polcat]        ; Read keyboard and dispatch
        beq     loop
        ldx     keymap
1       cmpa    ,x+
        bne     2f              ; Not a match
        ldx     ,x              ; Get target address
        jsr     ,x              ; JSR to it
        bra     loop

2       leax    2,x             ; Next entry
        ldb     ,x
        bne     1b
        bra     loop

drawbnk ldy     #bnkpos
        lda     bank_hi
        ldb     bank_lo
        jmp     drawwrd

drawbnk2 ldy     #bnkpos2
        lda     bank_hi
        ldb     bank_lo
        jmp     drawwrd

drawadr ldy     #addrpos
        ldd     addr
        jmp     drawwrd

map     ldd     #m_keys
        std     keymap
        clr     addr
        clr     addr+1
        jmp     mdraw

m_prev  ldd     #-256
        bra     m_resel

m_next  ldd     #256
        bra     m_resel

m_left  ldd     #-1
        bra     m_resel

m_right ldd     #1
        bra     m_resel

m_up    ldd     #-16
        bra     m_resel

m_down  ldd     #16
        bra     m_resel

m_resel pshs    d
        jsr     xorsel          ; Clear existing selection
        puls    d
        addb    bank_lo         ; Adjust selected bank
        adca    bank_hi
        sta     bank_hi
        stb     bank_lo
        jsr     xorsel          ; Attempt to update selection
        bne     mdraw           ; Went off page - redraw
        lbra    drawbnk         ; Update bank number
        
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
xorsel  leas    -2,s
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
mdraw   jsr     clrscn          ; Clear screen
        ldx     #map_menu       ; Draw static text
        jsr     draw
        jsr     drawbnk         ; Draw bank number
mdraw1  lda     bank_hi         ; Save selected bank
        ldb     bank_lo
        pshs    d
        cmpb    #$fc            ; Compute page
        bhs     4f
        deca
4       sta     page
        ldb     #$fc
        sta     bank_hi         ; Move to 1st bank in page
        stb     bank_lo
        ldy     #text
1       ldb     #'-'|$40
        jsr     is_free
        beq     2f
        ldb     #'X'
2       stb     ,y+
        inc     bank_lo
        bne     3f
        inc     bank_hi
3       tfr     y,d
        andb    #$f             ; Have we reached the 16th bank?
        bne     1b
        leay    16,y            ; Move to the next line
        cmpy    #textend
        blo     1b
3       puls    d               ; Restore selected bank
        sta     bank_hi
        stb     bank_lo
        jmp     xorsel          ; Highlight it

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

view    ldd     #v_keys
        std     keymap
        jmp     vdraw

v_next  ldd     #128
        jsr     resel
        lbra    vdraw
                      
v_prev  ldd     #-128
        jsr     resel
        lbra    vdraw
                      
resel   addd    addr
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
                      
vdraw   jsr     clrscn
        ldx     #v_menu
        jsr     draw
        jsr     drawbnk
        jsr     drawadr
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

amode   ldd     #a_keys
        std     keymap
        clr     addr+1
        ; fall through

adraw   jsr     clrscn
        ldx     #a_menu
        jsr     draw
        jsr     drawbnk
        jsr     drawadr
        ldx     addr            ; Draw hex bytes
        leax    rom,x
        ldy     #text
1       lda     ,x+
        sta     ,y+
        tfr     x,d             ; Have we reached the 16th byte?
        andb    #$f              
        bne     1b
        leay    16,y             ; Move to next line
        cmpy    #textend
        blo     1b
        rts

a_next  ldd     #256
        jsr     resel
        lbra    adraw
                      
a_prev  ldd     #-256
        jsr     resel
        lbra    adraw

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
emode   jsr     clrscn
        jsr     mdraw1      ; Redraw map screen minus stext
        ldx     #etext
        jsr     draw
        jsr     xorsel      ; Deselect
        jsr     ebound      ; Compute bounds of erasure
        jsr     drawbnk     ; Draw starting bank #
1       pshs    x           ; Highlight banks to erase
        jsr     xorsel
        puls    x
        leax    -1,x
        beq     2f
        inc     bank_lo
        bne     1b
        inc     bank_hi
        bra     1b
2       jsr     drawbnk2    ; Draw ending bank #
3       jsr     [polcat]
        cmpa    #'N'
        beq     4f
        cmpa    #'Y'
        bne     3b
        jsr     erase
4       lbra    mdraw

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Computes boundary of bank erasure
;
; Inputs:
;   bank_lo, bank_hi - Bank to erase
;
; Outputs:
;   bank_lo, bank_hi - First bank to erase
;   X - number of banks
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
ebound  lda     bank_hi
        ldb     bank_lo
        addd    #4              ; Convert to physical bank
        anda    #7              ; handle wraparound
        cmpd    #32
        bhs     1f
        andb    #~1             ; 2 banks/sec
        ldx     #2              ; Erase 2 banks
        bra     2f
1       andb    #~15
        ldx     #16             ; Bank count
2       subd    #4              ; Back to logical
        anda    #7              ; handle wraparound
        sta     bank_hi         ; move to starting bank
        stb     bank_lo
        rts
        
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
exit    jsr     clrscn
        leas    2,s             ; Unwind the stack
        rts
        
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
is_free
; x=bank to check
; Output
;  Z - set if bank is empty
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        ldx     #$c000
1       lda     ,x
        coma
        bne     2f
        leax    139,x           ; Sample the bank using a prime
        cmpx    #$d000
        blo     1b
        clra
2       rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
clrscn  
; Clears the screen
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        ldx     #text
        lda     #$60
1       sta     ,x+
        cmpx    #text+$200
        bne     1b
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Draws static text
; X - pointer to text block (as established by stext macro)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        
draw
        ldy     ,x++
        cmpy    #$ffff
        beq     9f
        leay    text,y
1       lda     ,x+
        beq     draw
        ora     #$40
        sta     ,y+
        bra     1b
9       rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
drawwrd bsr     drawbyt
        exg     a,b
drawbyt pshs    a
        lsra
        lsra
        lsra
        lsra
        bsr     drawnyb
        puls    a
drawnyb anda    #$0f
        cmpa    #10
        bge     1f
        adda    #$70
        bra     2f
1       adda    #'A'-10
2       sta     ,y+
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Erase bank
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

preamb  lda        #$aa
        sta        $caaa
        lda        #$55
        sta        $c555
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Tables
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

kmap    macro
        fcb     \1
        fdb     \2
        endm

m_keys  kmap    'P',    m_prev 
        kmap    'N',    m_next
        kmap    kleft,  m_left
        kmap    kright, m_right
        kmap    kup,    m_up
        kmap    kdown,  m_down
        kmap    'H',    view
        kmap    'A',    amode
        kmap    'E',    emode
        kmap    'X',    exit
        fcb     0

v_keys  kmap    'P',    v_prev 
        kmap    'N',    v_next
        kmap    'M',    map
        kmap    'A',    amode
        kmap    'X',    exit
        fcb     0

a_keys  kmap    'P',    a_prev 
        kmap    'N',    a_next
        kmap    'M',    map
        kmap    'H',    view
        kmap    'X',    exit
        fcb     0

stext   macro
        fdb     \1*32+\2
        fcn     \3
        endm

map_menu
        stext   0,24,   "BANK"
        stext   6,24,   "(E)RASE"
        stext   7,24,   "(H)EX"
        stext   8,24,   "(A)SCII"
        stext   9,24,   "(N)EXT"
        stext   10,24,  "(P)REV"
        stext   11,24,  "E(X)IT"
        fdb     $ffff

bnkpos  equ     text+32*1+24
bnkpos2 equ     text+32*3+24
addrpos equ     text+32*4+24

v_menu
        stext   0,24,   "BANK"
        stext   3,24,   "ADDR"
        stext   6,24,   "(E)RASE"
        stext   7,24,   "(M)AP"
        stext   8,24,   "(A)SCII"
        stext   9,24,   "(N)EXT"
        stext   10,24,  "(P)REV"
        stext   11,24,  "E(X)IT"
        fdb     $ffff

a_menu
        stext   0,26,   "BANK"
        stext   3,26,   "ADDR"
        stext   6,24,   "(E)RASE"
        stext   7,24,   "(M)AP"
        stext   8,24,   "(H)EX"
        stext   9,24,   "(N)EXT"
        stext   10,24,  "(P)REV"
        stext   11,24,  "E(X)IT"
        fdb     $ffff

etext
        stext   0,24,   "BANK"
        stext   2,24,   " TO"
        stext   6,22,   "ERASE ALL"
        stext   7,22,   "SELECTED"
        stext   8,22,   "BANKS?"
        stext   10,22,  "(Y)ES"
        stext   11,22,  "(N)O"
        fdb     $ffff

e1pos   equ     text+5*32+6
e2pos   equ     e1pos+8

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Global variables
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
page    fcc     0
addr    fdb     0       ; Address within bank to show (view mode)
keymap  fdb     m_keys

the_end
        end     main
