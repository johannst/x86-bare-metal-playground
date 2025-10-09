/* SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>
 */

OUTPUT_FORMAT(elf32-i386)
OUTPUT_ARCH(i386)
ENTRY(_entry)

SECTIONS {
    .mbr(0x7c00) : {
        */mbr-32.o(.text)
        */bios_call-32.o(.text)
        */main-32.o(.text)
        */main-32.o(.rodata*)

        /* MBR magic */
        . = 0x7c00 + 510;
        BYTE(0x55);
        BYTE(0xaa);
    }
    ASSERT(ADDR(.mbr) == 0x7c00, "mbr section must be located at 0x7c00")
    ASSERT(SIZEOF(.mbr) == 512, "mbr section must be exactly 512 bytes")

    .shstrtab : {
        * (.shstrtab*)
    }
    /DISCARD/ : { *(.*) }
}
