// -- BOOT TEXT SECTION ---------------------------------------------------------

.code16
.intel_syntax noprefix

.section .boot, "ax", @progbits
.global _entry
_entry:
    // Disable interrupts.
    cli

    // Clear segment selectors.
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax

    // Set cs to 0x0000, as some BIOSes load the MBR to either 07c0:0000 or 0000:7c000.
    jmp 0x0000:entry_rm16

entry_rm16:
    // Set video mode 13h, see [1].
    //   * 320x200 graphic mode
    //   * 256 colors (8bit per pixel)
    //   * 0xA0000 screen address
    //
    // [1] http://www.ctyme.com/intr/rb-0069.htm
    // [2] https://en.wikipedia.org/wiki/Mode_13h (shows color palette)
    mov ax, 0x13
    int 0x10

    // Set blue screen and halt if setting video mode failed.
    jnc 2f
    mov ah, 0xb
    mov bx, 1
    int 0x10
1:
    hlt
    jmp 1b
2:

    // Enable A20 address line.
    in al, 0x92
    or al, 2
    out 0x92, al

    // Load GDT descriptor.
    lgdt [gdt_desc]

    // Enable protected mode (set CR0.PE bit).
    mov eax, cr0
    or  eax, (1 << 0)
    mov cr0, eax

    // Far jump which loads segment selector (0x0008) into cs.
    // 0x0008 -> RPL=0, TI=0(GDT), I=1
    jmp 0x0008:entry_pm32

.code32
entry_pm32:
    // Select data segment selector (0x0010) for ds.
    mov ax, gdt_data - gdt
    mov ds, ax

    // Initialize stack pointer.
    // Real Mode memory (https://wiki.osdev.org/Memory_Map_(x86)
    //   0x00000500 - 0x00007BFF | 29.75 KiB | conventional memory
    mov esp, 0x7c00

    // Enter zmbr.zig:kmain.
    // Should not return, but for safety we emit a call rather than a jmp.
    call kmain

1:
    hlt
    jmp 1b

// -- RODATA SECTION ------------------------------------------------------------

.section .rodata, "a", @progbits
.balign 8
gdt:
    .8byte 0x0000000000000000 // 0x00 | null descriptor
    .8byte 0x00cf9a000000ffff // 0x08 | 32 bit, code (rx), present, dpl=0, g=4K, base=0, limit=fffff
gdt_data:
    .8byte 0x00cf92000000ffff // 0x10 | 32 bit, data (rw), present, dpl=0, g=4K, base=0, limit=fffff
gdt_desc:
    .2byte (. - gdt - 1)  // size
    .4byte gdt            // address
