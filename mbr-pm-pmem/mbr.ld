/* SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>
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
        */mbr-32.o(.text)
        */bios_call-32.o(.text)
        /* MBR magic */
        . = 0x7c00 + 510;
        BYTE(0x55);
        BYTE(0xaa);
    }
    ASSERT(ADDR(.mbr) == 0x7c00, "mbr section must be located at 0x7c00")
    ASSERT(SIZEOF(.mbr) == 512, "mbr section must be exactly 512 bytes")

    .stage2(0x7e00) : {
        */stage2-32.o(.text)
        */stage2-32.o(.rodata*)
        /* compiler_rt: include code/data used, we link with gc-sections */
        *libcompiler_rt*.o(.text.*)
        *libcompiler_rt*.o(.data.*)
        /* properly size the section */
        . = 0x7e00  + 16 * 512;
    }
    ASSERT(SIZEOF(.stage2) == 16 * 512, "mbr loads exactly 16 sectors")
    /**
     * seabios only supports 128 * 512 sectors per call [1].
     * [1] https://github.com/qemu/seabios/blob/106549a4362f6b499da522f8f8f5ed9f98388f87/src/block.c#L627
     */
    ASSERT(SIZEOF(.stage2) / 512 < 129, "stage2 should not be larger than 128 * 512 bytes")

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
