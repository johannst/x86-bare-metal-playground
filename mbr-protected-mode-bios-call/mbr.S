// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

.intel_syntax noprefix

.code16

.text
.global _entry
_entry:
    // Disable interrupts.
    cli

    // Set CS to 0, as some BIOSes load the MBR to either 07c0:0000 or 0000:7c000.
    jmp 0:rm16

rm16:
    // Enable A20 address line (fast A20 gate).
    in al, 0x92
    or al, 2
    out 0x92, al

    // Load pm32 GDT descriptor.
    lgdt [pm_gdt_descriptor]

    // Enable protected mode (set CR0.PE bit).
    mov eax, cr0
    or  eax, (1 << 0)
    mov cr0, eax

    // Far jump which loads segment selector (0x0008) into cs.
    // 0x0008 -> RPL=0, TI=0(GDT), I=1
    jmp 0x8:pm32

.code32
pm32:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax

    mov esp, 0x7c00
    call kmain
1:
    hlt
    jmp 1b

// Protected mode (32 bit) gdt table.
.balign 8
pm_gdt:
.8byte 0                   // 0x00 | Null entry
.8byte 0x00cf9a000000ffff  // 0x08 | 32 bit, code (rx), present, dpl=0, g=4K, base=0, limit=fffff
.8byte 0x00cf92000000ffff  // 0x10 | 32 bit, data (rw), present, dpl=0, g=4K, base=0, limit=fffff
.8byte 0x00009a000000ffff  // 0x18 | 16-bit, code (rx), present, dpl=0, g=1B, base=0, limit=0ffff
pm_gdt_end:

// Protected mode gdt table descriptor.
pm_gdt_descriptor:
.2byte pm_gdt_end - pm_gdt - 1
.4byte pm_gdt
