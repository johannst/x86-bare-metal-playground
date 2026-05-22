// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

/**
 * This boot sector does quite a bit of work and build on top of knowledge
 * acquired in different examples in this repository.
 *
 * It fetches the system memory map using E820 bios call.
 * See mbr-rm-e820-asm/ for details.
 *
 * It loads a second stage from disk using.
 * See mbr-pm-disk-lba/ for details.
 *
 * It sets up an initial idendity mapped page table and entern long mode.
 * See mbr-lm-enter-asm/ for details.
 */

// GDT segment selector.
#define KERN32_CODE 0x08
#define KERN32_DATA 0x10
#define KERN64_CODE 0x18
#define KERN64_DATA 0x20

// Physical address to store the E820 entries fetched.
// Memory is organized as follows:
//   E820 +  0: cnt -> u8
//   E820 +  8: e820 entry -> 24 byte
//   E820 + 32: e820 entry -> 24 byte
//   ...
#define E820       0x0500
// Physical address of early boot stack.
#define BOOT_STACK 0x7c00
// Physical address for the initial PML4, PDPT0, and PD0 tables.
#define PML4T      0x1000
#define PDPT0      0x2000
#define PD0        0x3000

// Bits for entries in the paging structures.
#define PG_PRESENT (1 << 0)
#define PG_RW      (1 << 1)
#define PG_SIZE    (1 << 7)

.intel_syntax noprefix

.code16
.text
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

    // Set CS to 0, as some BIOSes load the MBR to either 07c0:0000 or 0000:7c000.
    jmp 0:rm16

// LBA - disk address packet.
lba_pkt:
    .byte  0x10    // Size of this disk packet in bytes (16).
    .byte  0       // Reserved.
    .2byte 20      // Number of blocks to read (sectors 512 bytes?) to read.
    .4byte 0x7e00  // Destination address (seg16:off16).
    .8byte 1       // Starting lba block number (0 indexed, MBR is at 0).

rm16:
    // Load stage2 from disk into memory.
load_stage2:
    // Disk extended read.
    mov ah, 0x42
    // Bios puts boot disk into dl.
    // mov dl, #drive
    lea si, [lba_pkt]
    int 0x13
    // Quirk: BIOS on my laptop enables IF flag.
    cli

    // Fetch the system memory map using the E820 bios call and store the
    // entries at physical address starting from E820.
e820_get_map:
    // Get pointer to e820 entry counter (u8*).
    lea si, [E820]
    mov byte ptr[si], 0
    // Get pointer to first e820 entry (e820*).
    lea di, [E820 + 8]
    // Load b"SMAP" magic string.
    mov edx, 0x534D4150
    // Continuation code, start with first e820 memap entry.
    xor bx, bx
e820_get_entry:
    // At most 64 entries for now, halt on overflow.
    cmp byte ptr[si], 64
1:
    je   1b

    // Load bios call number.
    mov ax, 0xe820
    // Load size of e820 entry.
    mov cx, 24
    // BIOS call.
    int 0x15
    // Halt on error.
1:
    jc 1b

    // Advance pointer to next e820 entry.
    add  di, 24
    // Increment entry counter.
    inc  byte ptr[si]
    // Check if continuation code is back to 0, and if so stop iterating.
    test bx, bx
    jnz  e820_get_entry

enter_pm32:
    // Enable A20 address line (fast A20 gate).
    in  al, 0x92
    or  al, 2
    out 0x92, al

    // Load GDT descriptor.
    lgdt [gdt_descriptor]

    // Enable protected mode (set CR0.PE bit).
    mov eax, cr0
    or  eax, (1 << 0)
    mov cr0, eax

    // Far jump which loads segment selector (0x08) into cs.
    // 0x08 -> RPL=0, TI=0(GDT), I=1
    jmp KERN32_CODE:pm32

.code32
pm32:
    // Setup a simple paging by identity mapping the first 1GB.
setup_page_table:
    // Zero out PML4T, PDPT0 and PD0 tables.
    xor eax, eax
    mov ecx, 4096 / 4 * 3
    mov edi, PML4T
1:
    mov  [edi], eax
    add  edi, 4
    loop 1b

    // Setup PML4TE0 entry to point to PDPT0.
    mov dword ptr [PML4T], PDPT0 | PG_RW | PG_PRESENT

    // Setup PDPT0E0 entry to point to PD0.
    mov dword ptr [PDPT0], PD0 | PG_RW | PG_PRESENT

    // Setup PD0E[0.512] entries as leaf (2MB pages), starting at phys addr 0.
    // -> Identity the first 1GB.
    mov eax, 0x00000000 | PG_SIZE | PG_RW | PG_PRESENT
    xor edx, edx
    mov ecx, 512
1:
    mov dword ptr [PD0 + edx], eax
    add eax, 0x00200000
    add edx, 8
    loop 1b

enable_paging:
    // Setup pointer to root paging structure in CR3.
    mov edi, PML4T
    mov cr3, edi

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

    // Far jump which loads segment selector (0x20) into cs.
    // 0x20 -> RPL=0, TI=0(GDT), I=1
    jmp KERN64_CODE:lm64

.code64
lm64:
    mov rsp, BOOT_STACK
    call main
1:
    hlt
    jmp 1b

// GDT table.
.balign 8
gdt:
.8byte 0                   // 0x00 | Null entry
.8byte 0x00cf9a000000ffff  // 0x08 | 32 bit, code (rx), present, dpl=0, g=4K, base=0, limit=fffff
.8byte 0x00cf92000000ffff  // 0x10 | 32 bit, data (rw), present, dpl=0, g=4K, base=0, limit=fffff
.8byte 0x00af9a000000ffff  // 0x18 | 64 bit, code (rx), present, dpl=0, g=4K, base=0, limit=fffff
.8byte 0x00af92000000ffff  // 0x20 | 64 bit, data (rw), present, dpl=0, g=4K, base=0, limit=fffff
gdt_end:

// GDT table descriptor.
gdt_descriptor:
.2byte gdt_end - gdt - 1
.4byte gdt

// MBR magic.
.fill 510 - (. - rm_entry), 1, 0x00
.byte 0x55, 0xaa
