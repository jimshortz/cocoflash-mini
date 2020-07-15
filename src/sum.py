import sys

# simple checksum
f = open(sys.argv[1], "rb")
buf = f.read()
cksum = sum(buf) & 0xffff
print(hex(cksum), len(buf))
