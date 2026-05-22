/* SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>
 */

OUTPUT_FORMAT(elf32-i386)
OUTPUT_ARCH(i386)
ENTRY(_entry)

SECTIONS {
    /**
     * Bootsector, master boot record (MBR).
     * The bios loads the bootsector (512 bytes) at address 0x7c00 and
     * jumps to it.
     */
    .mbr(0x7c00) : {
        */mbr-32.o(.text)
        */stage1-32.o(.text)
        */bios_call-32.o(.text)
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
     *
     * We link in compiler_rt functions as needed. We rely on the fact
     * that zig links each function as own section into libcompiler_rt,
     * such that we can link with --gc-sections (or relesae build) and
     * the linker will only include the functions into our image which
     * we really reference.
     */
    HIDDEN(_stage2_start = .);
    .stage2 : {
        KEEP(*/stage2-32*.o(.text*))
        KEEP(*/stage2-32*.o(.data*))
        KEEP(*/stage2-32*.o(.rodata*))
        KEEP(*/stage2-32*.o(.bss*))
        /* compiler_rt: include code/data used, we link with gc-sections */
        *libcompiler_rt*.o(.text.*)
        *libcompiler_rt*.o(.data.*)
        /* Align up to the next 512 byte boundary and emit a byte */
        . = ALIGN(512) - 1;
        BYTE(0xa5);
    }
    HIDDEN(_stage2_end= .);
    ASSERT((_stage2_end - _stage2_start) % 512 == 0, "stage2 should be multiple of 512 bytes")
    /**
     * seabios only supports 128 * 512 sectors per call [1].
     * [1] https://github.com/qemu/seabios/blob/106549a4362f6b499da522f8f8f5ed9f98388f87/src/block.c#L627
     */
    ASSERT((_stage2_end - _stage2_start) / 512 < 129, "stage2 should not be larger than 128 * 512 bytes")

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
