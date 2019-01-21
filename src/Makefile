CFLAGS=-Wall -O2

ifeq	($(OS),WIN32)
ROM2WAV=rom2wav.exe
MAKEMENU=makemenu.exe
STAGE=cocoflash-mini-0.9
DIST=$(STAGE)-win32.zip
else
ROM2WAV=rom2wav
MAKEMENU=makemenu
STAGE=cocoflash-mini-0.9
DIST=$(STAGE)-linux.tar.gz
endif

targets:        $(DIST)

$(ROM2WAV):	rom2wav.c
	$(CC) $(CFLAGS) -o $(ROM2WAV) rom2wav.c -lm

$(MAKEMENU):	makemenu.c
	$(CC) $(CFLAGS) -o $(MAKEMENU) makemenu.c

menu.bin:	menu.asm
	asm6809 -o menu.bin -l menu.lst menu.asm

map.bin:	map.asm
	asm6809 -C -o map.bin -l map.lst map.asm

map.rom:	map.asm
	asm6809 -dROM -o map.rom -l map.rom.lst map.asm

loader.bin:	loader.asm
	asm6809 -C -o loader.bin -l loader.lst loader.asm

loader.rom:	loader.asm
	asm6809 -dROM -o loader.rom -l loader.rom.lst loader.asm

%.wav:	%.bin
	makewav -n$< -c -r $< -o$@

$(DIST): $(ROM2WAV) $(MAKEMENU) loader.wav map.wav menu.bin loader.rom map.rom 
ifeq	($(OS),WIN32)
	-rm $@
	zip $@ $^
else
	-rm -rf $(STAGE)
	mkdir $(STAGE)
	cp $^ $(STAGE)
	strip $(STAGE)/$(ROM2WAV)
	strip $(STAGE)/$(MAKEMENU)
	tar -czf $@ $(STAGE)
endif

# Optional targets that make menu building easier
menu.wav:	menu.rom rom2wav
	./rom2wav -e menu.rom -omenu.wav

menu.rom:	menu.csv makemenu menu.bin
	./makemenu -bmenu.bin menu.csv menu.rom

clean:
	-rm *.wav *.bin *.lst *.rom $(ROM2WAV) $(MAKEMENU)
