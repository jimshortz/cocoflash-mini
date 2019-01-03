# CocoFLASH-mini
Lightweight CocoFLASH programming software for the Coco 1/2

# Overview

The CocoFLASH is a nifty piece of hardware produced by [Retro
Innovations](http://www.go4retro.com/products/CocoFLASH/).  It is a 8MB flash
ROM cartridge for the Radio Shack Color Computer series.  Its massive size
allows for numerous titles to be loaded onto the cartridge and it includes a
menu program for choosing the title at boot time.

CocoFLASH also comes with very nice software for reprogramming the ROM and customizing the menu.  It
allows the menu to be customized using BASIC and new software to be downloaded via DriveWire.  Unfortunately
these features require 64KB of RAM and Extended Color BASIC.  Not all CoCos are as nicely equipped,
especially my CoCo 2 with 16KB of RAM.

So, I have written a set of replacement tools that only require 4KB of RAM and Color BASIC.  This should
work on any model of CoCo, though it has currently only been tested on a 16KB CoCo 2.

# Philosophy

The idea for this project came from the `c2t` software used in the Apple II
world.  To transfer software to the target computer, one simply connects a host
computer's sound card to the cassette port, types a single command on the
target computer, and plays back a single WAV file from the host.  No further
user interaction is required.  While the process is multi-stage, delays are
built into the WAV file to allow the target to do its work.

Running on the "lowest common denominator" CoCo hardware requires careful
conservation of RAM.  This means that:

* All target code is written in assembler.
* As much work as possible is offloaded to the host.

Sticking to assembler also eliminates compatibility differences between the
different versions of BASIC.

The term "host" is used to describe the modern computer used to facilitate
downloading of new ROMs to the "target" computer (a CoCo).  Binaries are
provided for Linux, Windows, and MacOS X.  The host tools are written in
"vanilla" C so any host with a C compiler should be able to be used.  Obviously,
this host must have a sound card and be capable of playing WAV files.

# Programming a ROM

An audio cable is required to connect the host to the target.  The original
CoCo cassette cable should work.  If you don't have one you can make your own or
order a replacement from [Cloud9](https://www.frontiernet.net/~mmarlette/Cloud-9/Hardware/Cables.html).

Programming the CocoFLASH is a multi-step process:
1. Download a ROM image to the host computer.
1. Choose a target bank.
1. Run `rom2wav` to produce a WAV file.
1. Type `CLOADM:EXEC` on the CoCo and press ENTER.
1. Play loader.wav to download the programming software.
1. Play the WAV file produced in step 2.  This step can be repeated to do
   multiple ROMS.
1. Press the RESET button

Example:
```
rom2wav -b28 EDTASM.ccc -oedtasm.wav
```

Will create generate `edtasm.wav` from the `EDTASM.ccc` binary and place it at
bank 28.  Use `rom2wav` with no arguments to see a full list of options.

By default, programming will fail if any block of the target ROM is already in use.
Passing the `-e` option will cause the target blocks to be erased first.  *Use with caution*
as this could cause neighboring ROMs to be erased as well due to idiosyncrasies of the 
CocoFLASH ROM and banking structure.  Consult the CocoFLASH documentation for an explanation
of this or simply always choose a starting bank of 28 plus a multiple of 32.

# Updating the menu

This project also provides a replacement for the CocoFLASH's BASIC-based menu.
The layout of the menu is kept in a text file on the host computer.  The host
regenerates the menu binaries and they are downloaded to the target using the  
same process as ROM cartridges.

The text file is a simple comma separated value (CSV) file.  The first field is
the name of the entry the user will see.  It should be 30 characters or less
and will be translated to upper case.  The second field is the bank number.
It may be specified in decimal, hex, or octal using the C conventions (e.g. 123,
0x20, 0377).  The last field is the "config" value.  For more information on
these values please consult the CocoFLASH manual.

Menu files may also contain blank lines or comment lines (prefixed with a
semicolon).  The parser is pretty lame, so don't get crazy with it :-)

Process for updating the menu:
1. Edit `menu.csv` using your editor of choice.
1. Run `makemenu menu.csv menu.rom` to produce a ROM image.
1. Run `rom2wav -b0 -e menu.rom -omenu.wav` to produce a WAV file.
1. Type `CLOADM:EXEC` on the CoCo and press ENTER.
1. Play `loader.wav`.
1. Play `menu.wav`.

Users may find it more convenient to edit the CSV *prior* to downloading
target ROMs as it makes managing the banks easier.  Also, the downloads
can be combined into a single session i.e. `loader.wav`, `menu.wav`, `rom1.wav`,
`rom2.wav`, etc.

# Building

Recompiling requires a standard `gcc` toolchain plus the following tools:

* `asm6809` assembler (https://www.6809.org.uk/asm6809/)
* `makewav` from the Toolshed project (https://github.com/boisy/toolshed).

After installing these prerequisites, simply type `make` from the `src` directory.

# Credits

The idea came from Egan Ford's `c2t` utility for the Apple IIs (https://github.com/datajerk/c2t).

The core ROM programming/erase routines came from the original CocoFLASH software
written by Barry Nelson (https://github.com/go4retro/CocoFLASH).

`rom2wav` is based on `makewav` from the Toolshed project (https://github.com/boisy/toolshed).
