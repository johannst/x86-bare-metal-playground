// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

// Real Mode memory map [1]
//   0x00000-0x003FF 1 KiB        Real Mode IVT
//   0x00400-0x004FF 256 bytes    BDA (BIOS data area)
//   0x00500-0x07BFF 29.75 KiB    Conventional memory
//   0x07C00-0x07DFF 512 bytes    OS BootSector
//   0x07E00-0x7FFFF 480.5 KiB    Conventional memory
//   0x80000-0x9FFFF 128 KiB      EBDA (Extended BIOS Data Area)
//   0xA0000-0xBFFFF 128 KiB      Video display memory
//   0xC0000-0xC7FFF 32 KiB       Video BIOS
//   0xC8000-0xEFFFF 160 KiB      BIOS Expansions
//   0xF0000-0xFFFFF 64 KiB       Motherboard BIOS
//
//
// To enter long mode one needs to
//   - enable protected mode and
//   - setup paging (at least 4-level).
// See Intel Manual Vol3 - 10.8.5 Initializing IA-32e Mode.
//
// 4-level paging uses the following paging structures
//   - PML4 (page map table level 4)
//   - PDPT (page directory pointer table)
//   - PD   (page directory)
//   - PT   (page table)
// See Intel Manual Vol3 - Table 4-2 Paging Structures.
//
// Every paging structure is 4096 bytes and in long mode each entry in a
// paging structure is 8 bytes.
//   -> Each paging structure contains 512 entries.
//   -> Paging structures must be 4k aligned.
// See Intel Manual Vol3 - Figure 4-11 Formats of CR3 and Paging-Structure
//                         Entries with 4-Level Paging and 5-Level Paging.
//
// 4-level paging is setup as follows:
//   - CR3 points to the first paging structure.
//   - CR4.PAE =1
//   - IA32_EFER.LME = 1
//   - CR0.PG = 1
//
// When mapping a page using all 4 levels its size is 4K (single PT entry).
// Larger pages can be mapped when setting the page size (7) bit in higher
// levels of the page table hierarchy.
//   - 2MB page: set page size bit in PD entry
//   - 1GB page: set page size bit in PDPT entry
//
// With the support of long mode, 2MB pages are always supported. However,
// 1GB pages are an optional feature and support can be checked via cpuid.
//    mov eax, 0x80000001
//    cpuid
//
//    test edx, (1 << 29)   // long mode supported?
//    jz not_supported
//    ..
//
//    test edx, (1 << 26)   // 1 GB pages supported?
//    jz not_supported
//    ..

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
    // Write string into VGA test mode buffer.
    // (Assumes that BIOS initialized VGA in text mode).
    xor rcx, rcx
1:
    mov al, byte ptr[msg + rcx]
    mov byte ptr[0xb8000 + 2 * rcx + 0], al    // character
    mov byte ptr[0xb8000 + 2 * rcx + 1], 0xa   // color
    inc rcx
    cmp rcx, (msg_end - msg)
    jne 1b

1:
    hlt
    jmp 1b

msg:
.ascii "Hello from ia-32e mode"
msg_end:

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
