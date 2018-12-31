;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; CocoFlash boot menu
;
; Runs at startup and allows user to choose a program to boot.
;
;-----------------------------------------------------------------------
;
; Author:       Jim Shortz
; Date:         December 30, 2018
;
; Target:       Radio Shack Color Computer
; Assembler:    asm6809 cross assembler
;
; This software is PUBLIC DOMAIN.  The author does not care one iota
; what you do with it.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        org     $c000
        setdp   0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; CoCo ROM entry vectors
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
polcat  equ     $a000
chrout  equ     $a002

; Hardware registers
config  equ     65380
bank_lo equ     65381
bank_hi equ     65382
rom_en  equ     $ffde 
mpak    equ     $ff7f
reset   equ     $fffe

; Memory locations
coldst  equ     $71             ; Cold start flag
text    equ     $0400           ; Text screen
mstart  equ     text+(32*2)     ; First menu entry screen pos
mend    equ     text+(32*14)    ; Last menu entry screen pos
ramorg  equ     $600

; Key codes
kdown   equ     $0a
kup     equ     $5e
kleft   equ     $08
kright  equ     $09
kent    equ     $0d

; Misc constants
reclen  equ     32              ; Length of a menu record
pagelen equ     12              ; Menu items per page
mwidth  equ     28              ; Number of characters in a menu item
scwidth equ     32              ; Width of the screen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Moves program from ROM to RAM and transfers control to RAM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
reloc
        leas    -2,s
        leax    tabstart,pcr    ; Ending source address
        stx     0,s
        leax    main,pcr        ; Starting source address
        ldy     #ramorg         ; Starting target address
1       lda     ,x+
        sta     ,y+
        cmpx    0,s
        bne     1b
        leas    2,s
        jmp     ramorg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Main control loop for menu
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
main    
        ; Find size of table
        ldx     #tabstart
1       lda     ,x
        beq     2f
        leax    reclen,x
        bra     1b
2       stx     last,pcr

        ; Draw static parts of screen
        lbsr    clrscn
        leax    header,pcr
        ldy     #text
        ldb     #32
        lbsr    cpy
        ldy     #mend+32
        ldb     #32
        lbsr    cpy
      
draw 
        ; Draw menu entries 
        ldx     top,pcr
        ldy     #mstart+2
1       cmpx    last,pcr
        bge     2f
        cmpy    #mend
        bge     2f
        lbsr    drawent
        bra     1b
2       stx     bottom,pcr

        ; Clear extra lines
        lda     #$60
3       cmpy    #mend
        bgt     4f
        sta     ,y+
        bra     3b

        ; Read input
4       jsr     [polcat]
        beq     4b        
        cmpa    #kdown
        lbeq    sel_down
        cmpa    #kup
        lbeq    sel_up
        cmpa    #kleft
        lbeq    page_up
        cmpa    #kright
        lbeq    page_down
        cmpa    #kent
        lbeq    done
        bne     draw

sel_up
        ldx     sel,pcr
        cmpx    top,pcr
        bgt     1f
        ldx     bottom,pcr      ; Wrap to bottom
1       leax    -reclen,x
        stx     sel,pcr
        lbra    draw

sel_down
        ldx     sel,pcr
        leax    reclen,x
        cmpx    bottom,pcr
        blt     1f
        ldx     top,pcr         ; Wrap to top
1       stx     sel,pcr
        lbra    draw

page_down
        ldx     top,pcr
        leax    pagelen*reclen,x
        cmpx    last,pcr        ; Skip if past end
        bge     1f
        stx     top,pcr
        stx     sel,pcr
1       lbra    draw
        
page_up
        ldx     top,pcr
        leax    -pagelen*reclen,x
        cmpx    first,pcr       ; Skip if before beginning
        blt     1f
        stx     top,pcr
        stx     sel,pcr
1       lbra    draw

done    
        ldx     sel,pcr
        lda     mwidth+2,x      ; Config bits
        pshs    a
        ldd     mwidth,x        ; Bank #
        ; NOTE - From this point on, nothing in the ROM is accessible
        sta     bank_hi
        stb     bank_lo
        clr     rom_en          ; Enable ROM
        clr     coldst          ; Reset cold start flag
        puls    a
        sta     config
        anda    #32             ; If bit 5 unset, activate multi-pak slot 4
        bne     1f
        lda     mpak
        ora     #3
        sta     mpak
1       jmp     [reset]
        
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Copy B bytes of memory from X to the screen memory Y.  Sets normal
; video attributes.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
cpy
        lda     ,x+
        ora     #$40
        sta     ,y+
        decb
        bne     cpy
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Draws a menu line
; Inputs:
;       X - Pointer to entry to draw
;       Y - Screen address to draw to
; Outputs:
;       X - Pointer to next entry
;       Y - Screen address of next line
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
drawent
        leas    -1,s
        lda     #$40            ; attr = (menu == sel) ? 0 : $40
        cmpx    sel,pcr
        bne     1f
        lda     #$00    
1       sta     0,s
        ldb     #mwidth         ; Copy text
2       lda     ,x+
        anda    #$3f            ; Set attribute bits
        ora     0,s
        sta     ,y+
        decb
        bne     2b
        leax    reclen-mwidth,x     ; Move to next record
        leay    scwidth-mwidth,y    ; Move to next line
        leas    1,s
        rts
        
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Clears the screen
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
clrscn  
        ldx     #text
        lda     #$60
1       sta     ,x+
        cmpx    #text+$200
        bne     1b
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Screen text
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

header  fcc     "         CHOOSE A ROM:          "
footer  fcc     "UP/DN=SELECT LT/RT=PAGE ENT=RUN "

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Variables
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
first   fdb     tabstart
last    fdb     0
top     fdb     tabstart                ; Entry on top line of screen
bottom  fdb     0                       ; Entry on bottom line +1
sel     fdb     tabstart                ; Pointer to selected entry

        align   32,0
tabstart    equ *
; makemenu.c will append the menu entries here.  Do not place anything else
; after "tabstart"
        end     main
