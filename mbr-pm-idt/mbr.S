// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

// This example sets up a protected mode IDT with a few IDT gates (vector
// entries).
//
// The IDT can have up to 255 gates, and gates 0-31 are reserved for exceptions [1].
// On exception (w/o privilege change), the following is pushed on the stack
//     eflags, cs, eip, (error code)
// Some exceptions push an error code, but not all of them, see the table in [1].
//
// Note: In this example we are using the `int N` instruction to invoke the
// interrupt handler. This will never push an error code onto the stack,
// even if the hardware generated exception would do so. Additionally, with `intN`,
// the eip pushed is the address after the `int N` instruction. For hardware
// exceptions that may not be true, some exceptions push the address of the
// faulting instruction, such that a iret can retry the instruction. The list in [2]
// gives details about each hardware generated exception.
//
// We invoke the reserved exception numbers because that suffices to setup a
// small IDT with just a few entries.
//
// [1] Intel Manual Vol3 - 6.3.1 External Interrupts
// [2] Intel Manual Vol3 - 6.15 Exception and Interrupt reference

.intel_syntax noprefix

.code16

.text
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

    // Patch offset in IDT gate 0.
    lea eax, [int0_handler]
    mov word ptr[pm_idt + 8 * 0 + 0], ax
    shr eax, 16
    mov word ptr[pm_idt + 8 * 0 + 6], ax

    // Patch offset in IDT gate 1.
    lea eax, [int1_handler]
    mov word ptr[pm_idt + 8 * 1 + 0], ax
    shr eax, 16
    mov word ptr[pm_idt + 8 * 1 + 6], ax

    // Patch offset in IDT gate 8.
    lea eax, [int8_handler]
    mov word ptr[pm_idt + 8 * 8 + 0], ax
    shr eax, 16
    mov word ptr[pm_idt + 8 * 8 + 6], ax

    // Load the IDT desciptor.
    lidt [pm_idt_descriptor]

    // Trigger interrupt 0 & 1.
    int 0
    int 1

    mov word ptr[0xb8000], 0xa00 | 'P'
    mov word ptr[0xb8002], 0xa00 | 'M'
    mov word ptr[0xb8004], 0xa00 | ' '
    mov word ptr[0xb8006], 0xa00 | 'I'
    mov word ptr[0xb8008], 0xa00 | 'D'
    mov word ptr[0xb800a], 0xa00 | 'T'

    // Trigger a double fault because int 4 gate is not present.
    int 4
1:
    hlt
    jmp 1b

int0_handler:
    mov word ptr[0xb80a0], 0xb00 | 'I'
    mov word ptr[0xb80a2], 0xb00 | 'N'
    mov word ptr[0xb80a4], 0xb00 | 'T'
    mov word ptr[0xb80a6], 0xb00 | '0'
    iret

int1_handler:
    mov word ptr[0xb80a8], 0xc00 | 'I'
    mov word ptr[0xb80aa], 0xc00 | 'N'
    mov word ptr[0xb80ac], 0xc00 | 'T'
    mov word ptr[0xb80ae], 0xc00 | '1'
    iret

int8_handler:
    mov word ptr[0xb80b0], 0xd00 | 'I'
    mov word ptr[0xb80b2], 0xd00 | 'N'
    mov word ptr[0xb80b4], 0xd00 | 'T'
    mov word ptr[0xb80b6], 0xd00 | '8'
1:
    // Treat double fault as fatal.
    hlt
    jmp 1b

// The interrupt descriptor table (IDT) in 32-bit protected mode consists
// of up to 256 entries (can be less). Each gate (entry) describes one
// interrupt / trap and is 8-bytes long.
//
// 32-bit IDT gate [1]
//   u16 offset15_0
//   u16 selector
//   u8  unused
//   u8  type         |P:7, DPL:6-5, 0:4, GATE TYPE:3-0|
//   u16 offset31_16
//
// [1] https://wiki.osdev.org/Interrupt_Descriptor_Table#Gate_Descriptor
// [2] Intel Manual Vol3 - 6.11 IDT descriptors

// Protected mode (32 bit) idt table.
.balign 8
pm_idt:
// Gate 0
.2byte 0    // offset15_0
.2byte 0x8  // cs
.byte  0    // (unused)
.byte  0x8F // present, dpl=0, 32-bit trap gate
.2byte 0    // offset31_16
// Gate 1
.2byte 0    // offset15_0
.2byte 0x8  // cs
.byte  0    // (unused)
.byte  0x8F // present, dpl=0, 32-bit trap gate
.2byte 0    // offset31_16
// Gate 2 - Gate 7 (not present)
.8byte 0
.8byte 0
.8byte 0
.8byte 0
.8byte 0
.8byte 0
// Gate 8 - double fault handler (exception during exception handling).
.2byte 0    // offset15_0
.2byte 0x8  // cs
.byte  0    // (unused)
.byte  0x8F // present, dpl=0, 32-bit trap gate
.2byte 0    // offset31_16
pm_idt_end:

// Protected mode idt table descriptor.
pm_idt_descriptor:
.2byte pm_idt_end - pm_idt - 1
.4byte pm_idt

// Protected mode (32 bit) gdt table.
.balign 8
pm_gdt:
.8byte 0                   // 0x00 | Null entry
.8byte 0x00cf9a000000ffff  // 0x08 | 32 bit, code (rx), present, dpl=0, g=4K, base=0, limit=fffff
.8byte 0x00cf92000000ffff  // 0x10 | 32 bit, data (rw), present, dpl=0, g=4K, base=0, limit=fffff
pm_gdt_end:

// Protected mode gdt table descriptor.
pm_gdt_descriptor:
.2byte pm_gdt_end - pm_gdt - 1
.4byte pm_gdt
