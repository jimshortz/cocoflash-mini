CFLAGS=-Wall -g

targets:        rom2wav makemenu loader.wav map.wav loader.rom map.rom menu.bin

rom2wav:	rom2wav.c
	gcc $(CFLAGS) -o rom2wav rom2wav.c -lm

makemenu:	makemenu.c
	gcc $(CFLAGS) -o makemenu makemenu.c

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

# Optional targets that make menu building easier
menu.wav:	menu.rom rom2wav
	./rom2wav -e menu.rom -omenu.wav

menu.rom:	menu.csv makemenu menu.bin
	./makemenu -bmenu.bin menu.csv menu.rom

clean:
	rm *.wav *.bin *.lst *.rom rom2wav makemenu
