OUTPUT_FORMAT(elf32-i386)
ENTRY(_entry)

SECTIONS {
    /**
     * 0x00500-0x07BFF free to used memory (rm16).
     * Mark to memory to store the number of e820 entries as well as the e820 entries.
     */
    . = 0x500;
    _e820_start = .;
    . += 8 /* entry counter */ + 64 * 24 /* sizeof(e820 entry) */;
    _e820_end = .;

    . = 0x7c00;
    _stack_top = .;

    .mbr : {
        *mbr-16.o(.text)
    }
    ASSERT(ADDR(.mbr) == 0x7c00, "mbr section must be located at 0x7c00")
    ASSERT(SIZEOF(.mbr) == 512, "mbr section must be exactly 512 bytes")

    /*/DISCARD/ : { *(.*) }*/
    /*rest      : { *(.*) }*/
}
