// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

.intel_syntax noprefix

/**
 * This example demonstrates the minimal setup required to transition between
 * kernel (ring 0) and user (ring 3) privilege in 64-bit long mode.
 *
 * The steps in the concrete example are as follows:
 * - Enter 32-bit protected mode.
 * - Setup paging (with user access) and enter 64-bit long mode.
 * - Setup required data structures GDT, IDT, TSS.
 * - Transition to ring 3 (user) using a manually crafted interrupt frame and by
 *   executing an iretq instruction.
 * - Return to ring 0 (kernel) by invoking a software interrupt in ring 3.
 * - The ring 0 interrupt handler writes 'KERN' to the screen and returns to
 *   ring 3.
 * - In ring 3 the string 'USER' is written to the screen and the program spins.
 *
 * The TSS structure in 64-bit mode holds the stack pointers (RSP0, RSP1, RSP2)
 * used by the processor when transitioning from a lower privilege to a higher
 * (eg ring 3 -> ring 0). See the comment below for further details and
 * references into the Intel manual.
 */

// Kernel and user stack pointer.
// Pick some area in the free range 0x0500-0x7bff (see real mode memory map).
#define STACK_KERN 0x7000
#define STACK_USER 0x6000

// Segment selector requested privilege level (RPL) flags.
#define PL_KERN 0b00
#define PL_USER 0b11
#define PL_MASK 0b11

// Segment selector according to GDT setup in this concrete example.
#define SEL_KERN_CODE (0x08 | PL_KERN)
#define SEL_KERN_DATA (0x10 | PL_KERN)
#define SEL_USER_CODE (0x18 | PL_USER)
#define SEL_USER_DATA (0x20 | PL_USER)
#define SEL_TSS       (0x28 | PL_KERN)

// -- REAL MODE ----------------------------------------------------------------

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

    // Set CS to 0, as some BIOSes load the MBR to either 07c0:0000 or 0000:7c00.
    jmp 0x0:rm16

rm16:
    // Enable A20 address line (fast A20 gate).
    in  al, 0x92
    or  al, 2
    out 0x92, al

    // Load 32 bit pm GDT descriptor.
    lgdt [pm32_gdt_descriptor]

    // Enable protected mode (set CR0.PE bit).
    mov eax, cr0
    or  eax, (1 << 0)
    mov cr0, eax

    // Far jump which loads segment selector (0x0008) into cs.
    // 0x0008 -> RPL=0, TI=0(GDT), I=1
    jmp 0x8:pm32

// -- PROTECTED MODE -----------------------------------------------------------

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
    // In this example we also mark all entries to be accessible by user
    // privilege as we transition into user level and execute code from here as
    // well as write to the VGA area.
    //
    // See Intel Manual Vol3 - Figure 4-9. Linear-Address Translation to a
    //                         2-MByte Page using 4-Level Paging

// Bits for entries in the paging structures.
#define PG_PRESENT (1 << 0)
#define PG_RW      (1 << 1)
#define PG_USER    (1 << 2)
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
    mov dword ptr [PML4T], PDPT0 | PG_USER | PG_RW | PG_PRESENT

    // Setup PDPT0E0 entry to point to PD0.
    mov dword ptr [PDPT0], PD0 | PG_USER | PG_RW | PG_PRESENT

    // Setup PD0E0 entry as leaf marking a 2MB page, with physical addr 0.
    mov dword ptr [PD0], 0x00000000 | PG_SIZE | PG_USER |  PG_RW | PG_PRESENT

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
    jmp SEL_KERN_CODE:lm64

// -- LONG MODE ----------------------------------------------------------------

.code64
lm64:
    // Setup segment selectors.
    mov ax, SEL_KERN_DATA
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax

    // Setup kernel stack pointer.
    mov rsp, STACK_KERN

setup_tr:
    // Patch address to TSS in segment descriptor (GDT).
    lea eax, [lm64_tss]
    mov word ptr [lm64_gdt + SEL_TSS & ~PL_MASK + 0x2], ax

    // Load the TSS segment selector into the task register (TR).
    mov ax, SEL_TSS
    ltr ax

setup_idt:
    // Patch offset in IDT gate 0.
    lea rax, [int0_handler]
    mov word ptr[lm64_idt + 16 * 0 + 0], ax

    // Load the IDT descriptor.
    lidt [lm64_idt_descriptor]

return_to_user:
    // Prepare iretq frame on kernel stack to return to user privilege.
    push SEL_USER_DATA      // ss
    push STACK_USER         // rsp
    push 0x2                // rflags
    push SEL_USER_CODE      // cs
    push offset user_entry  // rip

    // Setup segment selectors for user privilege.
    mov ax, SEL_USER_DATA
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    // Pop iretq frame and transfer control to user privilege.
    iretq

// -- USER PRIVILEGE -----------------------------------------------------------

user_entry:
    // Trigger interrupt 0, transition to kernel privilege.
    int 0

    mov word ptr[0xb80a0], 0xe00 | 'U'
    mov word ptr[0xb80a2], 0xe00 | 'S'
    mov word ptr[0xb80a4], 0xe00 | 'E'
    mov word ptr[0xb80a6], 0xe00 | 'R'
1:
    jmp 1b

// -- INTERRUPT HANDLER --------------------------------------------------------

int0_handler:
    mov word ptr[0xb8000], 0xb00 | 'K'
    mov word ptr[0xb8002], 0xb00 | 'E'
    mov word ptr[0xb8004], 0xb00 | 'R'
    mov word ptr[0xb8006], 0xb00 | 'N'
    iretq

// -- GDT (32-bit Protected Mode) ----------------------------------------------

// Protected mode (32 bit) gdt table.
.balign 8
pm32_gdt:
.8byte 0                   // 0x00 | Null entry
.8byte 0x00cf9a000000ffff  // 0x08 | 32 bit, code (rx), present, dpl=0, g=4K, base=0, limit=fffff
.8byte 0x00cf92000000ffff  // 0x10 | 32 bit, data (rw), present, dpl=0, g=4K, base=0, limit=fffff
pm32_gdt_end:

// Protected mode gdt table descriptor.
pm32_gdt_descriptor:
.2byte pm32_gdt_end - pm32_gdt - 1
.4byte pm32_gdt

// -- GDT (64-bit Long Mode) ---------------------------------------------------

// Long mode (64 bit) gdt table.
.balign 8
lm64_gdt:
.8byte 0                   // 0x00 | Null entry
.8byte 0x00af9a000000ffff  // 0x08 | 64 bit, code (rx), present, dpl=0, g=4K, base=0, limit=fffff
.8byte 0x00af92000000ffff  // 0x10 | 64 bit, data (rw), present, dpl=0, g=4K, base=0, limit=fffff
.8byte 0x00affa000000ffff  // 0x18 | 64 bit, code (rx), present, dpl=3, g=4K, base=0, limit=fffff
.8byte 0x00aff2000000ffff  // 0x20 | 64 bit, data (rw), present, dpl=3, g=4K, base=0, limit=fffff
.8byte 0x000089000000000c  // 0x28 | 64 bit, tss lower, present, dpl=0, g=1b, base=0, limit=c=sizeof(tss)
.8byte 0x0000000000000000  // 0x30 | 64 bit, tss upper, base[63:32]=0
lm64_gdt_end:

// Long mode gdt table descriptor.
lm64_gdt_descriptor:
.2byte lm64_gdt_end - lm64_gdt - 1
.8byte lm64_gdt

// -- TSS ----------------------------------------------------------------------

// The Task State Segment (TSS) in 64-bit mode is used for stack switching on
// when an interrupt or exception executes at a more privileged level
// (in long mode hardware task switching is not supported).
//
// The TSS holds rsp{0,1,2} for handlers executing in ring{0,1,2} respectively.
//
// For 64-bit mode:
// - The TSS is described in [2].
// - The TSS segment descriptor placed in the GDT is described in [3].
//   Note: In 64-bit mode, the TSS descriptor is 16 bytes (takes 2 GDT entries).
//
// This example only transfers between ring 0 (kernel) and ring 3 (user),
// therefore it only needs the RSP0 field which is the stack when switching
// to ring 0. Due to size limitations (512 byte boot sector) this only defines
// the TSS partially.
//
// [1] Intel Manual Vol1 - 6.5.1 Call and Return Operation for Interrupt or
//                               Exception Handling Procedures
// [2] Intel Manual Vol3 - 8.7 Task Management in 64-bit Mode
// [3] Intel Manual Vol3 - 8.2.3 TSS Descriptor in 64-bit mode

.balign 8
lm64_tss:
.4byte 0             // reserved
.8byte STACK_KERN    // rsp0
// cut off ..

// -- IDT ----------------------------------------------------------------------

// Long mode (64 bit) idt table.
// See mbr-lm-idt/ for details.
//
// Note: The DPL in the gate defines which privilege level is allowed to invoke
// this gate via a software interrupt 'int N'. Since this example wants to enter
// from user level in this example it has to set DPL=PL_USER in the gate 0.
.balign 8
lm64_idt:
// Gate 0
.2byte 0                               // offset[15:0]
.2byte SEL_KERN_CODE                   // cs selector to load on interrupt
.byte  0                               // ist (unused)
.byte  (1 << 7) | (PL_USER << 5) | 0xF // present, dpl=3, 64-bit trap gate
.2byte 0                               // offset[31:16]
.4byte 0                               // offset[63:32]
.4byte 0                               // reserved
lm64_idt_end:

// Long mode idt table descriptor.
lm64_idt_descriptor:
.2byte lm64_idt_end - lm64_idt - 1
.8byte lm64_idt

// MBR magic.
.fill 510 - (. - _entry), 1, 0x00
.byte 0x55, 0xaa
