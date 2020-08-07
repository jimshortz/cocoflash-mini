PORT=/dev/ttyUSB0
stty 38400 < $PORT
sx $1 < $PORT > $PORT
