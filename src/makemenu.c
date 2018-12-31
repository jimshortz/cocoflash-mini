/***********************************************************************
 * makemenu.c
 *
 * Generates a CoCoFlash menu from a .csv file.
 *
 * Author:  Jim Shortz
 * Date:    Dec 30, 2018
 *
 * Target:  Win32, Linux, MacOS X
 **********************************************************************/
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

typedef unsigned short  uint16;
typedef unsigned char   uint8;

#define TEXT_WIDTH  28

char buffer[512];
const char* menu_file_name = "menu.csv";
const char* pgm_file_name = "menu.bin";
const char* out_file_name = "menu.rom";

#pragma pack(1)

/* Menu entry record (32 bytes) */
struct {
    char    text[TEXT_WIDTH];
    uint8   bank_hi;
    uint8   bank_lo;
    uint8   type;
    uint8   pad[1];
} entry;

void usage() {
    fprintf(stderr, "Usage: makemenu [-b<pgm_file>] <csv_file> <out_file>\n");
    fprintf(stderr, "Where:\n");
    fprintf(stderr, "   pgm_file - Menu code file (default %s)\n", pgm_file_name);
    fprintf(stderr, "   csv_file - Menu definition file (default %s)\n", menu_file_name);
    fprintf(stderr, "   out_file - Output ROM image (default %s)\n\n", out_file_name);
    exit(1);
}

FILE* open_or_die(const char* filename, const char* mode) {
    FILE* f = fopen(filename, mode);
    if (f == NULL) {
        fprintf(stderr, "Could not open %s\n", filename);
        exit(2);
    }
    return f;
}
       
void parse_args(int argc, char** argv) {
    int j;
    int anon_args = 0;

    for (j = 1; j < argc; j++) {
        if (*argv[j] == '-') {
            switch (tolower(argv[j][1])) {
                case 'b':
                    pgm_file_name = argv[j]+2;
                    break;
                case 'h':
                    usage();
                    break;
                default:
                    /* Bad option */
                    fprintf(stderr, "Unknown option\n");
                    usage();
                }
        }
        else {
            switch (anon_args++) {
                case 0:
                    menu_file_name = argv[j];
                    break;
                case 1:
                    out_file_name = argv[j];
                    break;
                default:
                    fprintf(stderr, "Unknown argument\n");
                    usage();
            }
        }
    }
}

/* Convert string to upper case */
void strupr(char* str) {
    char* p = str;
    while (*p) {
        *p = toupper(*p);
        p++;
    }
}

int main(int argc, char** argv) {
    FILE* pgm_file = NULL;      /* Binary of the menu code */
    FILE* menu_file = NULL;     /* The CSV describing the menu */
    FILE* out_file = NULL;      /* Combined output ROM image */
    char fmt[64];

    parse_args(argc, argv);
    pgm_file = open_or_die(pgm_file_name, "rb");
    menu_file = open_or_die(menu_file_name, "r");
    out_file = open_or_die(out_file_name, "wb");

    /* Copy menu code to output file */
    while (!feof(pgm_file)) {
        int len = fread(buffer, 1, sizeof(buffer), pgm_file);
        fwrite(buffer, 1, len, out_file);
    }

    /* Read menu entries */
    int line = 0;
    while (fgets(buffer, 256, menu_file)) {
        char* text;
        char* bankstr;
        char* typestr;
        uint16 bank;
        uint8 type;

        line++;
        buffer[255] = 0;

        /* Skip blank lines and comments */
        if (buffer[0] == '\r' || buffer[0] == '\n' || buffer[0] == ';') {
            continue;
        }

        memset(&entry, 0, sizeof(entry));

        /* Parse comma seperated values */
        text = strtok(buffer, ",");
        bankstr = strtok(NULL, ",");
        typestr = strtok(NULL, "\r\n");
        if (!text || !bankstr || !typestr) {
            fprintf(stderr, "Syntax error at line %d of %s\n", line, menu_file_name);
            fclose(out_file);
            remove(out_file_name);
            exit(3);
        }

        bank = strtol(bankstr, NULL, 0);
        type = strtol(typestr, NULL, 0);

        /* Format binary record */
        sprintf(fmt, "%-28.28s", text);
        strupr(fmt);
        memcpy(entry.text, fmt, TEXT_WIDTH);
        entry.bank_hi = bank >> 8;
        entry.bank_lo = bank & 0xff;
        entry.type = type;
        fwrite(&entry, sizeof(entry), 1, out_file);
    }

    /* Write final null entry */
    memset(&entry, 0, sizeof(entry));
    fwrite(&entry, sizeof(entry), 1, out_file);

    fclose(out_file);
    fclose(menu_file);
    fclose(pgm_file);

    return 0;
}    
