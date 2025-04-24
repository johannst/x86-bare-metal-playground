/*OUTPUT_FORMAT(binary)*/
OUTPUT_FORMAT(elf32-i386)
OUTPUT_ARCH(i386)

SECTIONS {
    . = 0x7c00;
    .boot     : {
        *(.boot)
    }
    .text     : { *(.text) }
    .data     : { *(.data) }
    .bss      : { *(.bss) }
    .rodata   : { *(.rodata) }
    _boot_end = .;

    . = 0x7c00 + 510;
    .mbr.magic : {
        BYTE(0x55);
        BYTE(0xaa);
    }

    /*/DISCARD/ : { *(.*) }*/
    /*rest      : { *(.*) }*/

    ASSERT(_boot_end - 0x7c00 < 510, "boot sector must fit in 510 bytes")
}
