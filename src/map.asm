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

m_resel leas    -3,s
        std     0,s             ; Save offset
        lda     bank_hi         ; Save old bank_hi
        sta     2,s
        jsr     xorsel
        ldd     0,s             ; Load offset
        addb    bank_lo         ; Adjust selected bank
        adca    bank_hi
        sta     bank_hi
        stb     bank_lo
        cmpa    2,s             ; Compare to old bank_hi
        leas    3,s
        lbne    mdraw           ; bank_hi changed - redraw whole screen
        jsr     drawbnk         ; Update bank number
        lbra    xorsel          ; Hilight new bank
        
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
xorsel  clra                    ; Convert bank_lo to screen address
        ldb     bank_lo         ; Column = low nibble of bank_lo
        andb    #$0f
        pshs    b
        ldb     bank_lo         ; Row = high nibble of bank_lo
        andb    #$f0
        lslb                    ; row*32
        rola
        orb     0,s             ; Add in row
        ldx     #text
        leax    d,x
        lda     ,x
        eora    #$40            ; XOR background bits at screen address
        sta     ,x
        puls    b
        rts
        
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
mdraw   jsr     clrscn          ; Clear screen
        ldx     #map_menu       ; Draw static text
        jsr     draw
        jsr     drawbnk         ; Draw bank number
        ldb     bank_lo         ; Save selected bank
        pshs    b
        clr     bank_lo
        ldy     #text
1       ldb     #'-'|$40
        jsr     is_free
        beq     2f
        ldb     #'X'
2       stb     ,y+
        inc     bank_lo
        beq     3f
        lda     bank_lo
        anda    #$f             ; Have we reached the 16th bank?
        bne     1b
        leay    16,y            ; Move to the next line
        bra     1b
3       puls    b               ; Restore selected bank
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
        ldx     #etext
        jsr     draw
        jsr     ebound
        pshs    y
        tfr     x,d
        ldy     #e1pos
        jsr     drawwrd
        puls    d
        ldy     #e2pos
        jsr     drawwrd
1       jsr     [polcat]
        cmpa    #'N'
        beq     9f
        cmpa    #'Y'
        bne     1b
        jsr     erase
9       jmp     mdraw

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Computes boundary of bank erasure
;
; Inputs:
;   bank_lo, bank_hi - Bank to erase
;
; Outputs:
;   X = first bank erased
;   Y = last bank erased
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
ebound  lda     bank_hi
        ldb     bank_lo
        addd    #4              ; Convert to physical bank
        anda    #7              ; handle wraparound
        cmpd    #32
        bhs     1f
        andb    #~1             ; 2 banks/sec
        subd    #4              ; Back to logical
        anda    #7              ; handle wraparound
        tfr     d,x
        addd    #1
        tfr     d,y
        rts
1       andb    #~7
        subd    #4              ; Back to logical
        anda    #7              ; handle wraparound
        tfr     d,x
        addd    #7              ; 8 banks/sec
        tfr     d,y
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

bnkpos  equ     text+32*1+26
addrpos equ     text+32*4+26

map_menu
        stext   0,26,   "BANK"
        stext   6,24, "(E)RASE"
        stext   7,24, "(H)EX"
        stext   8,24, "(A)SCII"
        stext   9,24, "(N)EXT"
        stext   10,24,"(P)REV"
        stext   11,24,"E(X)IT"
        fdb     $ffff

v_menu
        stext   0,26,    "BANK"
        stext   3,26,    "ADDR"
        stext   6,24, "(E)RASE"
        stext   7,24, "(M)AP"
        stext   8,24, "(A)SCII"
        stext   9,24,"(N)EXT"
        stext   10,24,"(P)REV"
        stext   11,24,"E(X)IT"
        fdb     $ffff

a_menu
        stext   0,26,    "BANK"
        stext   3,26,    "ADDR"
        stext   6,24, "(E)RASE"
        stext   7,24, "(M)AP"
        stext   8,24, "(H)EX"
        stext   9,24, "(N)EXT"
        stext   10,24,"(P)REV"
        stext   11,24,"E(X)IT"
        fdb     $ffff

etext
        stext   4,4,    " WILL ERASE BANKS"
        stext   5,4,    "  XXXX TO YYYY"
        stext   6,4,    "ARE YOU SURE (Y/N)"
        fdb     $ffff

e1pos   equ     text+5*32+6
e2pos   equ     e1pos+8

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Global variables
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
addr    fdb     0       ; Address within bank to show (view mode)
keymap  fdb     m_keys

the_end
        end     main
