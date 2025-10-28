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
    lgdt [pm32_gdt_descriptor]

    // Enable protected mode (set CR0.PE bit).
    mov eax, cr0
    or  eax, (1 << 0)
    mov cr0, eax

    // Far jump which loads segment selector (0x0008) into cs.
    // 0x0008 -> RPL=0, TI=0(GDT), I=1
    jmp 0x8:pm32

.code32
pm32:
    // Setup a simple paging scheme, by just identity mapping the first 2MB.
    //
    // In this example this is done by using 2MB pages, which means that only
    // three paging structures must be used, where the third level already maps a
    // page effectively. To be more precise, the entry 0 in the PD0 sets the
    // S bit (7), indicating that this entry maps a page rather than delegating
    // to another paging structure.
    //
    // Since a single PD entry covers 512 PT entries, where each PT entry
    // covers a 4K Page, the PDPT entry covers 512 * 4096 bytes -> 2MB.
    // Hence if a PD entry maps a page (S bit set), the entry maps a 2MB page.
    //
    // See Intel Manual Vol3 - Figure 4-9. Linear-Address Translation to a
    //                         2-MByte Page using 4-Level Paging

// Bits for entries in the paging structures.
#define PG_PRESENT (1 << 0)
#define PG_RW      (1 << 1)
#define PG_SIZE    (1 << 7)

// Address for the PML4, PDPT0, and PD0 table.
#define PML4T 0x1000
#define PDPT0 0x2000
#define PD0   0x3000

setup_page_table:
    // Zero out PML4T, PDPT0 and PD0 tables.
    xor eax, eax
    mov ecx, 4096 / 4 * 3
    mov edi, PML4T
1:
    mov [edi], eax
    add edi, 4
    loop 1b

    // Setup pointer to root paging structure in CR3.
    mov edi, PML4T
    mov cr3, edi

    // Setup PML4TE0 entry to point to PDPT0.
    mov dword ptr [PML4T], PDPT0 | PG_RW | PG_PRESENT

    // Setup PDPT0E0 entry to point to PD0.
    mov dword ptr [PDPT0], PD0 | PG_RW | PG_PRESENT

    // Setup PD0E0 entry as leaf marking a 2MB page, with physical addr 0.
    mov dword ptr [PD0], 0x00000000 | PG_SIZE | PG_RW | PG_PRESENT

enable_paging:
    // Set CR4.PAE = 1.
    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax

    // Set IA32_EFER.LME = 1.
    mov ecx, 0xc0000080
    rdmsr
    or eax, 1 << 8
    wrmsr

    // Set CR0.PG = 1 (enable paging).
    mov eax, cr0
    or eax, 1 << 31
    mov cr0, eax

enter_lm:
    // Load lm64 GDT descriptor.
    lgdt [lm64_gdt_descriptor]

    // Far jump which loads segment selector (0x0008) into cs.
    // 0x0008 -> RPL=0, TI=0(GDT), I=1
    jmp 0x8:lm64

.code64
lm64:
    // Patch offset in IDT gate 0.
    lea eax, [int0_handler]
    mov word ptr[lm64_idt + 8 * 0 + 0], ax
    shr eax, 16
    mov word ptr[lm64_idt + 8 * 0 + 6], ax
    shr eax, 16
    mov dword ptr[lm64_idt + 8 * 0 + 8], eax

    // Load the IDT desciptor.
    lidt [lm64_idt_descriptor]

    // Trigger interrupt.
    int 0
    // The following would trigger a hardware exception (vector 0). However our
    // int0_handler is not really compatible with it, as the "divide error exception"
    // pushes the address of the faulting instruction on the stack, and hence an
    // iretq would return to the div instruction again.
    // We could for example skip the div instruction by updating rip in the
    // exception frame on the stack in int0_handler, for example:
    //     add qword ptr [rsp], 3
    //xor rbx, rbx
    //div rax, rbx

    mov word ptr[0xb8000], 0xa00 | 'L'
    mov word ptr[0xb8002], 0xa00 | 'M'

    mov word ptr[0xb8004], 0xa00 | ' '
    mov word ptr[0xb8006], 0xa00 | 'I'
    mov word ptr[0xb8008], 0xa00 | 'D'
    mov word ptr[0xb800a], 0xa00 | 'T'
1:
    hlt
    jmp 1b

int0_handler:
    mov word ptr[0xb80a0], 0xb00 | 'I'
    mov word ptr[0xb80a2], 0xb00 | 'N'
    mov word ptr[0xb80a4], 0xb00 | 'T'
    mov word ptr[0xb80a6], 0xb00 | '0'
    iretq

// The interrupt descriptor table (IDT) in 64-bit long mode consists
// of up to 256 entries (can be less). Each gate (entry) describes one
// interrupt / trap and is 16-bytes long.
//
// 64-bit IDT gate [1]
//   u16 offset15_0
//   u16 selector
//   u8  ist
//   u8  type         |P:7, DPL:6-5, 0:4, GATE TYPE:3-0|
//   u16 offset31_16
//   uint32_t offset63_32;
//   uint32_t zero;

//
// [1] https://wiki.osdev.org/Interrupt_Descriptor_Table#Gate_Descriptor
// [2] Intel Manual Vol3 - 6.14.1 64-Bit Mode IDT

// Long mode (64 bit) idt table.
lm64_idt:
// Gate 0
.2byte 0    // offset15_0
.2byte 0x8  // cs
.byte  0    // (unused)
.byte  0x8F // present, dpl=0, 32-bit trap gate
.2byte 0    // offset31_16
.8byte 0    // offset63_32
lm64_idt_end:

lm64_idt_descriptor:
.2byte lm64_idt_end - lm64_idt - 1
.8byte lm64_idt

// Protected mode (32 bit) gdt table.
.balign 8
pm32_gdt:
.8byte 0                   // Null entry
.8byte 0x00cf9a000000ffff  // 32 bit, code (rx), present, dpl=0, g=4K, base=0, limit=fffff
.8byte 0x00cf92000000ffff  // 32 bit, data (rw), present, dpl=0, g=4K, base=0, limit=fffff
pm32_gdt_end:

// Protected mode (32 bit) gdt table descriptor.
pm32_gdt_descriptor:
.2byte pm32_gdt_end - pm32_gdt - 1
.4byte pm32_gdt

// Long mode (ia-32e, 32 bit) gdt table.
.balign 8
lm64_gdt:
.8byte 0                   // Null entry
.8byte 0x00af9a000000ffff  // 64 bit, code (rx), present, dpl=0, g=4K, base=0, limit=fffff
.8byte 0x00af92000000ffff  // 64 bit, data (rw), present, dpl=0, g=4K, base=0, limit=fffff
lm64_gdt_end:

// Long mode (ia-32e, 32 bit) gdt descriptor.
lm64_gdt_descriptor:
.2byte lm64_gdt_end - lm64_gdt - 1
.8byte lm64_gdt

// MBR magic.
.fill 510 - (. - _entry), 1, 0x00
.byte 0x55, 0xaa
