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
        */stage1-32.o(.text)
        /* MBR magic */
        . = 0x7c00 + 510;
        BYTE(0x55);
        BYTE(0xaa);
    }
    ASSERT(ADDR(.mbr) == 0x7c00, "mbr section must be located at 0x7c00")
    ASSERT(SIZEOF(.mbr) == 512, "mbr section must be exactly 512 bytes")

    . = ADDR(.mbr) + SIZEOF(.mbr);
    HIDDEN(_stage2_start = .);
    .stage2 : {
        KEEP(*/stage2-32.o(.text*))
        KEEP(*/stage2-32.o(.data*))
        KEEP(*/stage2-32.o(.rodata*))
        /* Align up to the next 512 byte boundary and emit a byte */
        . = ALIGN(512) - 1;
        BYTE(0xa5);
    }
    HIDDEN(_stage2_end= .);
    ASSERT((_stage2_end - _stage2_start) % 512 == 0, "stage2 should be multiple of 512 bytes")
}
