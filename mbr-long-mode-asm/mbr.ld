OUTPUT_FORMAT(elf64-x86-64)
ENTRY(_entry)

SECTIONS {
    .mbr(0x7c00) : {
        */mbr-64.o(.text)
    }
    ASSERT(ADDR(.mbr) == 0x7c00, "mbr section must be located at 0x7c00")
    ASSERT(SIZEOF(.mbr) == 512, "mbr section must be exactly 512 bytes")

    /*/DISCARD/ : { *(.*) }*/
    /*rest      : { *(.*) }*/

}
