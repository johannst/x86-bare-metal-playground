// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

#define KERN_CS 0x08
#define KERN_DS 0x10

// -- BOOT TEXT SECTION ---------------------------------------------------------

.code16
.intel_syntax noprefix

.section .text, "ax", @progbits
.global rm_entry
rm_entry:
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

// LBA - disk address packet.
lba_pkt:
    .byte 0x10     // Size of this disk packet in bytes (16).
    .byte 0        // Reserved.
    .2byte 16      // Number of blocks to read (sectors 512 bytes?) to read.
    .4byte 0x7e00  // Destination address (seg16:off16).
    .8byte 1       // Starting lba block number (0 indexed, MBR is at 0).

entry_rm16:
    // Disk extended read.
    mov ah, 0x42
    //mov dl, #drive // bios puts boot disk into dl
    lea si, [lba_pkt]
    int 0x13
    // Quirk: BIOS on my laptop enables IF flag.
    cli

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
    jmp KERN_CS:entry_pm32

.code32
entry_pm32:
    // Select data segment selector (0x0010) for ds.
    mov ax, KERN_DS
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax

    // Initialize stack pointer.
    // Real Mode memory (https://wiki.osdev.org/Memory_Map_(x86)
    //   0x00000500 - 0x00007BFF | 29.75 KiB | conventional memory
    mov esp, 0x7c00

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
