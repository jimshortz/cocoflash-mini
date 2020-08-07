import serial

def append_word(buf, word):
    high,low = divmod(word, 0x100)
    buf.append(high)
    buf.append(low)

def create_header(start_bank, kb_cnt, fname):
    buf = bytearray()
    append_word(buf, start_bank)
    append_word(buf, kb_cnt)
    buf.extend(bytes(fname.upper().ljust(16), 'utf-8'))
    return buf

fname = "dungeon.rom"
f = open(fname, "rb")
rom = f.read()

BATCH_SIZE = 1024
ser = serial.Serial('/dev/ttyUSB0', 38400, timeout=10)
bank = 304 | 0x8000
ser.write(create_header(bank, len(rom) // BATCH_SIZE, fname))

# Wait for go ahead signal
r = ser.read()
print("Got response", r)
if r == bytes("G", "utf-8"):
    pos = 0
    while pos < len(rom):
        ser.write(rom[pos:pos+BATCH_SIZE])
        r = ser.read()
        print("Got response", r)
        pos = pos + BATCH_SIZE
