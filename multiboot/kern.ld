ENTRY(_start)

SECTIONS
{
    . = 1M;
    .mbhdr : {
        KEEP(*(.mbhdr))
    }
    .text.boot : {
        *(.text.boot)
    }
    .text : {
        *(.text*)
    }
    .rodata ALIGN (0x1000) : {
        *(.rodata*)
    }
    .data ALIGN (0x1000) : {
        *(.data*)
    }
    .bss : {
        sbss = .;
        *(COMMON)
        *(.bss*)
        ebss = .;
    }
}
