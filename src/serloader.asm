BBOUT       equ     $FF20
BBIN        equ     $FF22
IntMasks    equ $50



**********************************************************************
* Test harness
**********************************************************************
            org     $600
            clra
            tfr     a, dp
            setdp   0
            ldx     #msg
            ldy     #msgend-msg
            bsr     DWWrite
            swi
            
            ldx     #$1000  ;* Read 8KB
            ldy     #8192
            bsr     DWRead
            swi

msg         fcb     "Hello world"
msgend
*******************************************************
*
* DWRead
*    Receive a response from the DriveWire server.
*    Times out if serial port goes idle for more than 1.4 (0.7) seconds.
*    Serial data format:  1-8-N-1
*    4/12/2009 by Darren Atkinson
*
* Entry:
*    X  = starting address where data is to be stored
*    Y  = number of bytes expected
*
* Exit:
*    CC = carry set on framing error, Z set if all bytes received
*    X  = starting address of data received
*    Y  = checksum
*    U is preserved.  All accumulators are clobbered
*

*******************************************************
* 38400 bps using 6809 code and timimg
*******************************************************
DWRead    clra                          ; clear Carry (no framing error)
          deca                          ; clear Z flag, A = timeout msb ($ff)
          tfr       cc,b
          pshs      u,x,dp,b,a          ; preserve registers, push timeout msb
          orcc      #IntMasks           ; mask interrupts
          tfr       a,dp                ; set direct page to $FFxx
          setdp     $ff
          leau      ,x                  ; U = storage ptr
          ldx       #0                  ; initialize checksum
          adda      #2                  ; A = $01 (serial in mask), set Carry

* Wait for a start bit or timeout
rx0010    bcc       rxExit              ; exit if timeout expired
          ldb       #$ff                ; init timeout lsb
rx0020    bita      <BBIN               ; check for start bit
          beq       rxByte              ; branch if start bit detected
          subb      #1                  ; decrement timeout lsb
          bita      <BBIN
          beq       rxByte
          bcc       rx0020              ; loop until timeout lsb rolls under
          bita      <BBIN
          beq       rxByte
          addb      ,s                  ; B = timeout msb - 1
          bita      <BBIN
          beq       rxByte
          stb       ,s                  ; store decremented timeout msb
          bita      <BBIN
          bne       rx0010              ; loop if still no start bit

* Read a byte
rxByte    leay      ,-y                 ; decrement request count
          ldd       #$ff80              ; A = timeout msb, B = shift counter
          sta       ,s                  ; reset timeout msb for next byte
rx0030    exg       a,a
          nop
          lda       <BBIN               ; read data bit
          lsra                          ; shift into carry
          rorb                          ; rotate into byte accumulator
          lda       #$01                ; prep stop bit mask
          bcc       rx0030              ; loop until all 8 bits read

          stb       ,u+                 ; store received byte to memory
          abx                           ; update checksum
          ldb       #$ff                ; set timeout lsb for next byte
          anda      <BBIN               ; read stop bit
          beq       rxExit              ; exit if framing error
          leay      ,y                  ; test request count
          bne       rx0020              ; loop if another byte wanted
          lda       #$03                ; setup to return SUCCESS

* Clean up, set status and return
rxExit    leas      1,s                 ; remove timeout msb from stack
          inca                          ; A = status to be returned in C and Z
          ora       ,s                  ; place status information into the..
          sta       ,s                  ; ..C and Z bits of the preserved CC
          leay      ,x                  ; return checksum in Y
          puls      cc,dp,x,u,pc        ; restore registers and return
          setdp     $00

*******************************************************
*
* DWWrite
*    Send a packet to the DriveWire server.
*    Serial data format:  1-8-N-1
*    4/12/2009 by Darren Atkinson
*
* Entry:
*    X  = starting address of data to send
*    Y  = number of bytes to send
*
* Exit:
*    X  = address of last byte sent + 1
*    Y  = 0
*    All others preserved
*

*******************************************************
* 38400 bps using 6809 code and timimg
*******************************************************

DWWrite   pshs      u,d,cc              ; preserve registers
          orcc      #IntMasks           ; mask interrupts
          ldu       #BBOUT              ; point U to bit banger out register
          lda       3,u                 ; read PIA 1-B control register
          anda      #$f7                ; clear sound enable bit
          sta       3,u                 ; disable sound output
          fcb       $8c                 ; skip next instruction

txByte    stb       ,--u                ; send stop bit
          leau      ,u+
          lda       #8                  ; counter for start bit and 7 data bits
          ldb       ,x+                 ; get a byte to transmit
          lslb                          ; left rotate the byte two positions..
          rolb                          ; ..placing a zero (start bit) in bit 1
tx0010    stb       ,u++                ; send bit
          tst       ,--u
          rorb                          ; move next bit into position
          deca                          ; decrement loop counter
          bne       tx0010              ; loop until 7th data bit has been sent
          leau      ,u
          stb       ,u                  ; send bit 7
          lda       ,u++
          ldb       #$02                ; value for stop bit (MARK)
          leay      -1,y                ; decrement byte counter
          bne       txByte              ; loop if more to send

          stb       ,--u                ; leave bit banger output at MARK
          puls      cc,d,u,pc           ; restore registers and return

