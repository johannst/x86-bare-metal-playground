OUTPUT_FORMAT(elf64-x86-64)
ENTRY(rm_entry)

SECTIONS {
    /**
     * Bootsector, master boot record (MBR).
     * The bios loads the bootsector (512 bytes) at address 0x7c00 and
     * jumps to it.
     */
    .mbr(0x7c00) : {
        */mbr-64.o(.text)
    }
    ASSERT(ADDR(.mbr) == 0x7c00, "mbr section must be located at 0x7c00")
    ASSERT(SIZEOF(.mbr) == 512, "mbr section must be exactly 512 bytes")

    .stage2(0x7e00) : {
        */main-64.o(.text)
        */main-64.o(.rodata*)
        */rt-64.o(.text)
        /* compiler_rt: include code/data used, we link with gc-sections */
        /* *libcompiler_rt*.o(.text.*) */
        /* *libcompiler_rt*.o(.data.*) */
        /* properly size the section */
        . = 0x7e00  + 20 * 512;
    }
    ASSERT(SIZEOF(.stage2) == 20 * 512, "mbr loads exactly 20 sectors")

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
