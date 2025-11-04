// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

.intel_syntax noprefix

/**
 * This example demonstrates the minimal setup required to transition between
 * kernel (ring 0) and user (ring 3) privilege in 32-bit protected mode.
 *
 * The steps in the concrete example are as follows.
 * - Enter 32-bit protected mode.
 * - Setup required data structures GDT, IDT, TSS.
 * - Transition to ring 3 (user) using a manually crafted interrupt frame and by
 *   executing an iret instruction.
 * - Return to ring 0 (kernel) by invoking a software interrupt in ring 3.
 * - The ring 0 interrupt handler writes 'KERN' to the screen and returns to
 *   ring 3.
 * - In ring 3 the string 'USER' is written to the screen and the program spins.
 *
 * The TSS structure is typically used for hardware based task switching,
 * however it also holds the stack pointer and stack segment selector used by
 * the  processor when transitioning from a lower privilege to a higher (eg
 * ring 3 -> ring 0). See the comment below for further details and references
 * into the intel manual.
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
    jmp 0x0:enter_pm

enter_pm:
    // Enable A20 address line (fast A20 gate).
    in  al, 0x92
    or  al, 2
    out 0x92, al

    // Load 32 bit pm GDT descriptor.
    lgdt [pm_gdt_descriptor]

    // Enable protected mode (set CR0.PE bit).
    mov eax, cr0
    or  eax, (1 << 0)
    mov cr0, eax

    // Far jump which loads segment selector (0x0008) into cs.
    // 0x0008 -> RPL=0, TI=0(GDT), I=1
    jmp SEL_KERN_CODE:pm_entry

// -- PROTECTED MODE -----------------------------------------------------------

.code32
pm_entry:
    // Setup segment selectors.
    mov ax, SEL_KERN_DATA
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax

    // Setup kernel stack pointer.
    mov esp, STACK_KERN

setup_tr:
    // Patch address to TSS in segment descriptor (GDT). This patches base[15:0]
    // which is sufficient since boot sector is loaded at 0x7c00-0x7dff.
    lea ax, [pm_tss]
    // Explicitly use "word ptr" to get asm failure if wrong source register size is used.
    mov word ptr [pm_gdt + SEL_TSS & ~PL_MASK + 0x2], ax

    // Load the TSS segment selector into the task register (TR). After this the
    // TSS can be referenced.
    mov ax, SEL_TSS
    ltr ax

setup_idt:
    // Patch offset in IDT gate 0, same as above patching offset[15:0] only.
    lea eax, [int0_handler]
    mov word ptr[pm_idt + 8 * 0 + 0], ax

    // Load the IDT desciptor.
    lidt [pm_idt_descriptor]

return_to_user:
    // Prepare iret frame on kernel stack to return to user privilege.
    push SEL_USER_DATA      // ss
    push STACK_USER         // esp
    push 0x2                // eflags
    push SEL_USER_CODE      // cs
    push offset user_entry  // eip

    // Setup segment selectors for user privilege.
    mov ax, SEL_USER_DATA
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    // ss is setup when popping the iret frame.

    // Pop iret frame and transfer control to user privilege.
    iret
1:
    hlt
    jmp 1b

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

// -- INTERRTUP HANDLER --------------------------------------------------------

int0_handler:
    mov word ptr[0xb8000], 0xb00 | 'K'
    mov word ptr[0xb8002], 0xb00 | 'E'
    mov word ptr[0xb8004], 0xb00 | 'R'
    mov word ptr[0xb8006], 0xb00 | 'N'
    iret

// -- GDT ----------------------------------------------------------------------

// Protected mode (32 bit) gdt table.
.balign 8
pm_gdt:
.8byte 0                   // 0x00 | Null entry
.8byte 0x00cf9a000000ffff  // 0x08 | 32 bit, code (rx), present, dpl=0, g=4K, base=0, limit=fffff
.8byte 0x00cf92000000ffff  // 0x10 | 32 bit, data (rw), present, dpl=0, g=4K, base=0, limit=fffff
.8byte 0x00cffa000000ffff  // 0x18 | 32 bit, code (rx), present, dpl=3, g=4K, base=0, limit=fffff
.8byte 0x00cff2000000ffff  // 0x20 | 32 bit, data (rw), present, dpl=3, g=4k, base=0, limit=fffff
.8byte 0x000089000000000c  // 0x28 | 32 bit, tss      , present, dpl=0, g=1b, base=0, limit=c=sizeof(pm_tss)
pm_gdt_end:

// Protected mode gdt table descriptor.
pm_gdt_descriptor:
.2byte pm_gdt_end - pm_gdt - 1
.4byte pm_gdt

// -- TSS ----------------------------------------------------------------------

// The Task State Segment (TSS) is a data structure mainly used for hardware
// task switching. However, it also carries information that will be used when
// an interrupt or exception executes at a more privileged level.
//
// From the Intel Manual Vol1 [1]
//     If the code segment for the handler procedure has the same privilege level
//     as the currently executing program or task, the handler procedure uses the
//     current stack; if the handler executes at a more privileged level, the
//     processor switches to the stack for the handler’s privilege level
//
//     If a stack switch does occur, the processor does the following:
//        [..]
//     2. Loads the segment selector and stack pointer for the new stack (that is,
//        is the stack for the privilege level being called) from the TSS into
//        the SS and ESP registers and switches to the new stack.
//
// The TSS holds esp{0,1,2} and ss{0,1,2} for handlers executing in ring{0,1,2}
// respectively.
//
// For 32-bit mode
// - the TSS is described in [2].
// - the TSS segment descriptor placed in the GDT is described in [3].
//
// This example only transfers between ring 0 (kernel) and ring 3 (user),
// therefore it only needs the esp0 & ss0 fields which are the stack and stack
// selector when switching to ring 0. Due to size limitations (512 byte boot
// sector) this only defines the TSS partially and the size in the TSS segment
// descriptor in the GDT is restricted accordingly.
//
// [1] Intel Manual Vol1 - 6.5.1 Call and Return Operation for Interrupt or
//                               Exception Handling Procedures
// [2] Intel Manual Vol3 - 8.2.1 Task-State Segment (TSS)
// [3] Intel Manual Vol3 - 8.2.2 TSS Descriptor

.balign 8
pm_tss:
.4byte 0             // prev task link + reserved
.4byte STACK_KERN    // esp0
.2byte SEL_KERN_DATA // ss0
.2byte 0             // reserved (required at least in qemu)
// cut off ..

// -- IDT ----------------------------------------------------------------------

// Protected mode (32 bit) idt table.
// See mbr-pm-idt/ for details.
//
// Note: The DPL in the gate defines which privilege level is allowed to invoke
// this gate via a software interrupt 'int N'. Since this example wants to enter
// from user level in this example it has to set DPL=PL_USER in the gate 0.
.balign 8
pm_idt:
// Gate 0
.2byte 0                               // offset[15:0]
.2byte SEL_KERN_CODE                   // cs selector to load on interrupt
.byte  0                               // (unused)
.byte  (1 << 7) | (PL_USER << 5) | 0xF // present, dpl=3, 32-bit trap gate
.2byte 0                               // offset[31:16]
pm_idt_end:

// Protected mode idt table descriptor.
pm_idt_descriptor:
.2byte pm_idt_end - pm_idt - 1
.4byte pm_idt
