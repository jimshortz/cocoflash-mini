/***********************************************************************
 * rom2wav.c
 *
 * Generates a WAV file from a CoCo ROM image suitable for downloading
 * by loader.asm.
 *
 * Author:  Jim Shortz
 * Date:    Dec 30, 2018
 *
 * Target:  Win32, Linux, MacOS X
 **********************************************************************/
#include <stdio.h>
#include <ctype.h>
#include <string.h>
#include <strings.h>
#include <libgen.h>
#include <stdlib.h>
#include <math.h>
#include <errno.h>

#define MAXPATHLEN 512
#define PI 3.1415926
#define BLOCK_SIZE 255
#define BATCH_SIZE 1024
#define BANNER_SIZE 44

#define ERASE_SECS_PER_KB 0.03
#define BCHECK_SECS_PER_KB 0.03
#define PGM_SECS_PER_KB 1.5

typedef unsigned int    uint32;
typedef unsigned short  uint16;
typedef unsigned char   uint8;

void open_infile();
void open_outfile();
void close_outfile();

int             sample_rate;
uint16          start_bank;
uint16          kb_count;
const char*     out_filename;
const char*     in_filename=NULL;
int             verbose;
int             erase;
FILE*           input;
FILE*           output;
int             input_length;
uint8           *buffer_1200,
                *buffer_2400;
int             buffer_1200_length,
                buffer_2400_length;

#pragma pack(1)

/* Describes ROM to CoCo loader */
struct {
    uint16  start_bank;
    uint16  kb_count;
    char    fname[16];
} pgm_header;

/* WAVE file header */
struct wav_header_t {
    char    id[4];
    uint32  chunk_size;
    char    format[4];
    char    sc1_id[4];
    uint32  sc1_size;
    uint16  audio_format;
    uint16  num_channels;
    uint32  sample_rate;
    uint32  byte_rate;
    uint16  block_align;
    uint16  bits_per_sample;
    char    sc2_id[4];
    uint32  sc2_size;
} wav_header;
    
uint16 swap_uint16(uint16 in) {
    return (in << 8) | (in >> 8);
}

uint32 swap_uint32(uint32 in) {
    return swap_uint16(in >> 16) | (swap_uint16(in & 0x0000ffff) << 16);
}

#ifdef __BIG_ENDIAN__

#define LE_UINT16(x) swap_uint16(x)
#define LW_UINT32(x) swap_uint32(x)
#define BE_UINT16(x) x
#define BE_UINT32(x) x

#else

#define LE_UINT16(x) x
#define LE_UINT32(x) x
#define BE_UINT16(x) swap_uint16(x)
#define BW_UINT32(x) swap_uint32(x)

#endif

void open_infile() {

    input = fopen(in_filename, "rb");
    if (input == NULL) {
        fprintf(stderr, "Unable to open %s\n\n", in_filename);
        exit(1);
    }

    /* Get size of ROM */
    fseek(input, 0, SEEK_END); 
    input_length = ftell(input);
    fseek(input, 0, SEEK_SET);

    kb_count = (input_length + BATCH_SIZE - 1)/BATCH_SIZE;

    if (verbose) {
        printf("ROM size is %d (%d KB)\n", input_length, kb_count);
    }
}

void open_outfile() {
    output = fopen(out_filename, "wb");

    if (output == NULL)
    {
        fprintf(stderr, "Could not open/create %s\n\n", out_filename);
        exit(2);
    }

    /* Leave space for WAVE header */
    fseek(output, sizeof(wav_header), SEEK_SET);
}

void close_outfile() {

    /* Write the WAVE header */
    int final_size = ftell(output);        

    memcpy(wav_header.id, "RIFF", 4);
    wav_header.chunk_size = LE_UINT32(final_size - 8);
    memcpy(wav_header.format, "WAVE", 4);
    memcpy(wav_header.sc1_id, "fmt ", 4);
    wav_header.sc1_size = LE_UINT32(16);
    wav_header.audio_format = LE_UINT16(1);
    wav_header.num_channels = LE_UINT16(1);
    wav_header.sample_rate = LE_UINT32(sample_rate);
    wav_header.block_align = LE_UINT16(1);
    wav_header.bits_per_sample = LE_UINT16(8);
    memcpy(wav_header.sc2_id, "data", 4);
    wav_header.sc2_size = LE_UINT32(final_size - sizeof(wav_header));

    fseek(output, 0, SEEK_SET);
    fwrite(&wav_header, 1, sizeof(wav_header), output);
    fclose(output);
}

unsigned char* sine_buffer(int length) {
    double increment = (PI * 2.0) / length;
    int i;
    unsigned char* buffer;

    buffer = malloc(length);
    if (buffer != NULL) {
        for (i = 0; i < length; i++) {
            buffer[i] = (sin(increment * i + PI) * 110.0) + 127.0;
        }
    }

    return buffer;
}

void fwrite_audio_byte(int byte, FILE * output) {
    int j;

    for (j = 0; j < 8; j++) {
        if (((byte >> j) & 0x01) == 0) {
            fwrite(buffer_1200, buffer_1200_length, 1, output);
        }
        else {
            fwrite(buffer_2400, buffer_2400_length, 1, output);
        }
    }
}

void write_block(uint8 type, const void* data, uint8 length) {
    uint8 sum = type + length;
    const uint8* p = (uint8*) data;
    const uint8* end = p + length;

    fwrite_audio_byte(0x55, output);
    fwrite_audio_byte(0x3c, output);
    fwrite_audio_byte(type, output);
    fwrite_audio_byte(length, output);

    while (p < end) {
        fwrite_audio_byte(*p, output);
        sum += *p++;
    }

    fwrite_audio_byte(sum, output);
    fwrite_audio_byte(0x55, output);
}

void write_leader() {
   int length = 128;

    while (length > 0) {
        fwrite_audio_byte(0x55, output);
        length--;
    }
}     

void write_silence(double seconds) {
    int samples = (double)sample_rate * seconds;

    while (samples > 0) {
        fputc(0x80, output);
        samples--;
    }
}

void parse_args(int argc, char** argv) {
    int j;

    for (j = 1; j < argc; j++)
    {
        if (*argv[j] == '-')
        {
            switch (tolower(argv[j][1]))
            {
            case 'b':
                if (argc <= ++j) {
                    fprintf(stderr, "Missing bank parameter\n");
                    exit(1);
                }
                errno = 0;
                start_bank = strtol(argv[j], NULL, 0);
                if (errno || start_bank < 0 || start_bank >= 2048) {
                    fprintf(stderr, "Invalid bank parameter: %s\n", argv[j]);
                    exit(1);
                }
                break;
            case 's':
                if (argc <= ++j) {
                    fprintf(stderr, "Missing sample rate parameter\n");
                    exit(1);
                }
                errno = 0;
                sample_rate = strtol(argv[j], NULL, 0);
                if (errno || sample_rate < 8000 || sample_rate > 96000) {
                    fprintf(stderr, "Invalid sample rate parameter: %s\n", argv[j]);
                    exit(1);
                }
                break;
            case 'o':
                if (argc <= ++j) {
                    fprintf(stderr, "Missing output file parameter\n");
                    exit(1);
                }
				out_filename = argv[j];
                break;
            case 'e':
                erase = 1;
                break;
            case 'v':
                verbose = 1;
                break;
            default:
                /* Bad option */
                fprintf(stderr, "Unknown option %s\n", argv[j]);
                exit(1);
            }
        } else if (in_filename == NULL) {
			in_filename = argv[j];	
        } else {
            fprintf(stderr, "Unknown argument %s\n", argv[j]);
            exit(1);
        }
    }
}

#ifndef _WIN32
/* Convert string to upper case */
void strupr(char* str) {
    char* p = str;
    while (*p) {
        *p = toupper(*p);
        p++;
    }
}
#endif

void copy_filename() {
    char* fname;
    int len;
    char buffer[512];

    strcpy(buffer, in_filename);
    fname = basename(buffer);
    len = strlen(fname);
    strupr(fname);

    if (len < 16) {
        memcpy(pgm_header.fname, fname, len);
        memset(pgm_header.fname+len, ' ', 16-len);
    } else {
        memcpy(pgm_header.fname, fname, 16);
    }
}

int main(int argc, char **argv)
{
    uint8   buffer[BATCH_SIZE];

    /* Initialize globals */
    sample_rate = 11250;
	out_filename = "file.wav";
    verbose = 0;
    
    if (argc < 2)
    {
        fprintf(stderr, "rom2wav version 0.9\n\n");
        fprintf(stderr, "Copyright (C) 2007 Tim Lindner\n");
        fprintf(stderr, "Copyright (C) 2013 Tormod Volden\n");
        fprintf(stderr, "Copyright (C) 2018 Jim Shortz\n\n");
        fprintf(stderr, "This program will generate a WAV file from a Color Computer ROM\n");
        fprintf(stderr, "suitable for downloading using loader.wav\n\n");
        fprintf(stderr, "Usage: %s [options] input-file\n", argv[0]);
        fprintf(stderr, " -b <val>    Starting bank number to program\n");
        fprintf(stderr, " -e          Erases ROM (MAY ERASE NEIGHBORING PROGRAMS)\n");
        fprintf(stderr, " -s <val>    Sample rate for WAV file (default %d samples per second)\n", sample_rate);
        fprintf(stderr, " -o <string> Output file name for WAV file (default: %s)\n", out_filename);
        fprintf(stderr, " -v          Print information about the conversion (default: off)\n\n");
        fprintf(stderr, "For <val> use 0x prefix for hex, 0 prefix for octal and no prefix for decimal.\n");

        exit(1);
    }

    parse_args(argc, argv);

    open_infile();
    open_outfile();

    /* Defined values */
//  buffer_1200_length = (double)sample_rate / 1200.0;
//  buffer_2400_length = (double)sample_rate / 2400.0;

    /* Using emperical measurment */
    buffer_1200_length = (double)sample_rate / 1094.68085106384;
    buffer_2400_length = (double)sample_rate / 2004.54545454545;
    
    buffer_1200 = sine_buffer(buffer_1200_length);
    buffer_2400 = sine_buffer(buffer_2400_length);

    if (buffer_1200 == NULL || buffer_2400 == NULL) {
        fprintf(stderr, "Could not allocate memory for sine buffers\n");
        return 2;
    }

    /* Write some initial silence just to get everything going */
    write_silence(0.25);

    /* Write header block */
    copy_filename();
    pgm_header.start_bank = BE_UINT16(start_bank | (erase ? 0x8000 : 0));
    pgm_header.kb_count = BE_UINT16(kb_count);

    if (verbose) {
        printf("Writing header: start_bank=%d erase=%d fname=%16.16s\n", start_bank, erase, pgm_header.fname);
    }

    write_leader();
    write_block(3, &pgm_header, sizeof(pgm_header));

    /* Give CoCo time to do the blank check and erase */
    write_silence(BCHECK_SECS_PER_KB * kb_count);
    if (erase) {
        write_silence(ERASE_SECS_PER_KB * kb_count);
    }

    /* Download ROM in 1K batches */
    int len;
    while ((len = fread(buffer, 1, BATCH_SIZE, input)) > 0) {
        unsigned char* p = buffer;

        /* Pad buffer with zeros */
        memset(buffer + len, 0, BATCH_SIZE - len);
        len = BATCH_SIZE;

        write_leader();

        /* Write data in 255 byte blocks */
        while (len > 0) {
            int block_len = (len > BLOCK_SIZE) ? BLOCK_SIZE : len;

            write_block(1, p, block_len);
            p += block_len;
            len -= block_len;
        }

        /* EOF block */
        write_block(0xff, NULL, 0);

        /* Write silence to give the CoCo time to do its work */
        write_silence(PGM_SECS_PER_KB);
    }


    fclose(input);
    close_outfile();
    free(buffer_1200);
    free(buffer_2400);

    if (verbose) {
        fprintf(stderr, "Generation complete.  To download, type the following command on the CoCo:\n");
        fprintf(stderr, "    CLOADM:EXEC\n");
        fprintf(stderr, "and press return.  Then from the PC, play loader.wav followed by %s\n",
                out_filename);
    }
    
    return 0;
}
