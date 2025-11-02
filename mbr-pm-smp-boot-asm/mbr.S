// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

.intel_syntax noprefix

/**
 * This example demonstrates a minimal smp bootup according to the description
 * in the intel manual [1]. During startup one processor is identified as the
 * BSP (bootstrap processor) while other processors are considered APs
 * (application processors).
 *
 * After the bios finished its initialization, it hands control over to the BSP
 * which starts executing the loaded boot sector. The APs are halted in the
 * wait-for-INIT state.
 *
 * APs can be woken up by sending them a sequence of IPIs (inter-process
 * interrupts). Specifically an INIT and a SIPI (start-up IPI).
 *
 * An IPI is send through the processors local APIC by writing to the ICR
 * (interrupt command register) [3]. The IPI is actually send after writing to
 * the lower-half of the 64 bit register.
 *
 * The SIPI carries a vector number (8 bit) which defines the APs entry point.
 * The entry point must be 4k page aligned and is given by (vector << 12).
 *
 * For minimalism this example only consists of the boot sector (512 bytes MBR),
 * which is loaded to 0x7c00 - 0x7dff by the bios (no need to disk access).
 * To provide an entry point for the APs starting on a 4k page, the
 * position-independent code between (rm_entry..rm_entry_end) is copied to
 * 0x8000. This code then does an far jump, which is always absolute, back into
 * the loaded boot sector.
 *
 * Since the whole example does not use any stack space it does not setup a
 * stack for the BSP or any AP.
 *
 * One additional note, this example sends broadcast IPIs. In a more realistic
 * scenario one may want to send directed IPIs to APs local APICs after
 * enumerating them through the MADT (acpi) table.
 *
 * High-level flow
 * - BSP starts in 16 bit real mode and then enters 32 bit protected mode.
 * - BSP copies rm_entry..rm_entry_end to 0x8000.
 * - BSP sends broadcast INIT-FINI IPIs with entry point 0x8000 to APs.
 * - BSP checks in by printing to its slot in the VGA area.
 * - APs wake up and start executing at 0x8000 in 16 bit real mode.
 * - APs enter 32 bit protected mode and also check in by printing to their
 *   slots in the VGA area.
 *
 * Intel Vol. 3A - System Programming Guide
 * [1] 9.4 multiple-processor (mp) initialization
 * [2] 11.6 issuing interprocessor interrupts
 * [3] 11.6.1 Interrupt Command Register (ICR)
 */

// MSR address for the APIC_BASE register.
#define MSR_IA32_APIC_BASE 0x1b

// APIC_BASE bits.
#define APIC_BASE_BSP_BIT (1 << 8)

// Register offsets for the local APIC relative to its base address.
#define APIC_ID_REG    0x20
#define APIC_LCR_REGL 0x300
#define APIC_LCR_REGH 0x310

// APIC LCR bits.
#define APIC_LCR_ALL_EXCL_SELF (0b11 << 18)
#define APIC_LCR_ASSERT        (1 << 14)
#define APIC_LCR_INIT          (0b101 << 8)
#define APIC_LCR_SIPI          (0b110 << 8)
#define APIC_LCR_PENDING       (1 << 12)

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
rm_entry_end:

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
    jmp 0x8:pm_entry

.code32
pm_entry:
    // Setup segment selectors.
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax

    // Copy real mode entry point to 0x8000, where APs will start executing.
    mov ecx, rm_entry_end - rm_entry
    lea esi, [rm_entry]
    mov edi, 0x8000
    rep movsb

    // Read APIC_BASE register (result will be in eax).
    mov ecx, MSR_IA32_APIC_BASE
    rdmsr

    // Check if this is the BSP processor, iff wake up other APs then checkin.
    // APs directly go to checkin.
    test eax, APIC_BASE_BSP_BIT
    jz   core_checkin

    // Get local APIC base address, mask off info bits (assume edx == 0).
    and eax, ~0xfff

    // IPI, send INIT to all APs and wait until delivered (polling).
    mov ebx, APIC_LCR_ALL_EXCL_SELF | APIC_LCR_ASSERT | APIC_LCR_INIT
    mov [eax + APIC_LCR_REGL], ebx
2:
    pause
    test dword ptr [eax + APIC_LCR_REGL], APIC_LCR_PENDING
    jnz  2b

    // IPI, send SIPI with vector=8 to all APs. This starts them at 0x8000.
    mov ebx, APIC_LCR_ALL_EXCL_SELF | APIC_LCR_ASSERT | APIC_LCR_SIPI | 8
    mov [eax + APIC_LCR_REGL], ebx

core_checkin:
    // Get local APIC base address (assume edx == 0)..
    mov ecx, MSR_IA32_APIC_BASE
    rdmsr
    and eax, ~0xfff

    // Read local APIC ID from register.
    mov eax, [eax + APIC_ID_REG]
    // [31:24] bit in xAPIC mode.
    shr eax, 24

    // Character to write to VGA area. This is based on the loca APIC ID,
    // which is a unique id assigned during boot by the bios. Use the APIC ID
    // rather than the core count to see if any core executes this code twice.
    add eax, 0xe00 | 'a'

    // Atomically increment the core_count variable.
    mov edi, 1
    lock xadd [core_count], edi

    // Compute slot in VGA area this processor will write to. Slot is based
    // on the core count, shift by 1 as in text mode entries are 16 bit.
    shl edi, 1
    add edi, 0xb8000

    // Write out character to VGA and halt.
    mov [edi], ax
1:
    hlt
    jmp 1b

core_count:
.4byte 0

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
