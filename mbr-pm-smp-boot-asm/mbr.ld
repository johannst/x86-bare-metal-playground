/* SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>
 */

OUTPUT_FORMAT(elf32-i386)
OUTPUT_ARCH(i386)
ENTRY(rm_entry)

SECTIONS {
    /**
     * Bootsector, master boot record (MBR).
     * The bios loads the bootsector (512 bytes) at address 0x7c00 and
     * jumps to it.
     */
    .mbr(0x7c00) : {
        */mbr-32.o(.text)
        /* MBR magic */
        . = 0x7c00 + 510;
        BYTE(0x55);
        BYTE(0xaa);
    }
    ASSERT(ADDR(.mbr) == 0x7c00, "mbr section must be located at 0x7c00")
    ASSERT(SIZEOF(.mbr) == 512, "mbr section must be exactly 512 bytes")

    /**
     * Discard any code/data not matched by any pattern above.
     * The idea being that we get undefined reference error when
     * linking and referencing something outside the listed objects.
     */
    /DISCARD/ : {
        *(.*text*)
        *(.*rodata*)
        *(.*data*)
        *(.*bss*)
    }
}
