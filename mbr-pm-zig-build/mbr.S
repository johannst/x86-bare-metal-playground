// SPDX-License-Identifier: MIT
//
// Copyright (c) 2026, Johannes Stoelp <dev@memzero.de>

#define KERN_CS 0x08
#define KERN_DS 0x10

// -- BOOT TEXT SECTION ---------------------------------------------------------

.code16

.section .text, "ax", @progbits
.global rm_entry
rm_entry:
    // Disable interrupts.
    cli

    xor %ax, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %ss
    mov %ax, %fs
    mov %ax, %gs

    // Far jump, load 0x0 into cs.
    ljmp $0x0, $entry_rm16

// LBA - disk address packet.
lba_pkt:
    .byte  0x10    // Size of this disk packet in bytes (16).
    .byte  0       // Reserved.
    .2byte 32      // Number of blocks to read (sectors 512 bytes?) to read.
    .4byte 0x7e00  // Destination address (seg16:off16).
    .8byte 1       // Starting lba block number (0 indexed, MBR is at 0).

entry_rm16:
    // Disk extended read.
    mov $0x42, %ah
    //mov dl, #drive // bios puts boot disk into dl
    lea (lba_pkt), %si
    int $0x13
    // Quirk: BIOS on my laptop enables IF flag.
    cli

    // Enable A20 address line.
    in  $0x92, %al
    or  $2, %al
    out %al, $0x92

    // Load GDT descriptor.
    lgdt gdt_desc

    // Enable protected mode (set CR0.PE bit).
    mov %cr0, %eax
    or  $1, %eax
    mov %eax, %cr0

    // Far jump which loads segment selector (0x0008) into cs.
    // 0x0008 -> RPL=0, TI=0(GDT), I=1
    ljmp $KERN_CS, $entry_pm32

.code32
entry_pm32:
    // Select data segment selector (0x0010) for ds.
    mov $KERN_DS, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %ss
    mov %ax, %fs
    mov %ax, %gs

    // Initialize stack pointer.
    // Real Mode memory (https://wiki.osdev.org/Memory_Map_(x86)
    //   0x00000500 - 0x00007BFF | 29.75 KiB | conventional memory
    mov $0x7c00, %esp

    // Write something to the screen to see that it's working.
    mov $80, %ecx
    xor %eax, %eax
1:
    movw $(2 << 8 | 'A'), 0xb8000(%eax)
    add $2, %eax
    loop 1b

    call stage2
1:
    hlt
    jmp 1b

.balign 8
gdt:
    .8byte 0x0000000000000000  // 0x00 | null descriptor
    .8byte 0x00cf9a000000ffff  // 0x08 | 32 bit, code (rx), present, dpl=0, g=4K, base=0, limit=fffff
    .8byte 0x00cf92000000ffff  // 0x10 | 32 bit, data (rw), present, dpl=0, g=4K, base=0, limit=fffff
    .8byte 0x00009a000000ffff  // 0x18 | 16-bit, code (rx), present, dpl=0, g=1B, base=0, limit=0ffff
gdt_desc:
    .2byte (. - gdt - 1)  // size
    .4byte gdt            // address
