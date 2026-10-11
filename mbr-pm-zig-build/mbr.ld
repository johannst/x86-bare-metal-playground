/* SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2026, Johannes Stoelp <dev@memzero.de>
 */

OUTPUT_FORMAT(elf32-i386)
ENTRY(rm_entry)

SECTIONS {
    /**
     * Bootsector, master boot record (MBR).
     * The bios loads the bootsector (512 bytes) at address 0x7c00 and
     * jumps to it.
     */
    .mbr(0x7c00) : {
        */mbr.o(.text)
        /* MBR magic */
        . = 0x7c00 + 510;
        BYTE(0x55);
        BYTE(0xaa);
    }
    ASSERT(ADDR(.mbr) == 0x7c00, "mbr section must be located at 0x7c00")
    ASSERT(SIZEOF(.mbr) == 512, "mbr section must be exactly 512 bytes")

    /**
     * Link the second stage bootloader at 0x7e00, directly behind the
     * MBR. The MBR (stage1) will load the whole stage2 from disk into
     * memory at address 0x7e00.
     */
    HIDDEN(_stage2_start = .);
    .stage2 : {
        KEEP(*/boot_zcu.o(.text*))
        KEEP(*/boot_zcu.o(.rodata*))
        /* Align up to the next 512 byte boundary and emit a byte */
        . = ALIGN(512) - 1;
        BYTE(0xa5);
    }
    HIDDEN(_stage2_end= .);
    ASSERT((_stage2_end - _stage2_start) % 512 == 0, "stage2 should be multiple of 512 bytes")
    ASSERT((_stage2_end - _stage2_start) / 512 <= 32, "stage2 should not be larger than 32 * 512 bytes")

    /**
     * Discard any code/data not matched by any pattern above.
     * The idea being that we get undefined reference error when
     * linking and referencing something outside the listed objects.
     */
    .shstrtab : {
        *(.*shstrtab*)
    }
    /DISCARD/ : {
        *(.*text*)
        *(.*rodata*)
        *(.*data*)
        *(.*bss*)
        *(.*common*)
        *(.*init*)
        *(.*fini*)
        *(.*ctors*)
        *(.*dtors*)
    }
}
