// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

#define ASM
#include "bios_call.h"
#undef ASM

.intel_syntax noprefix
.text

/* extern "C" bios_call(int, RegisterState*);
 *
 * This function assumes the x86 SystemV C abi, where arguments are
 * passed on the stack, and arguments are pushed right to left.
 *
 * Utility function to invoke bios interrupts from 32-bit protected
 * mode, by temporarily switching back to 16-bit real mode and back to
 * 32-bit protected mode after the bios interrupt.
 *
 * Steps of switching back to real mode are described in the manual.
 *   Intel Vol. 3A - System Programming Guide
 *   10.9.2 Switching Back to Real-Address Mode
 *
 * In our case this function is only used in a very controlled
 * environment during early boot and hence we can ignores some steps
 * like for example disabling paging, reloading idt and so on.
 *
 * One additional note. Usually one would use the "INT n"[1]
 * instruction to invoke a bios interrupt. However "n" must be known
 * at assembly time, as it is baked into the opcode as imm8.
 * In our case we accept the interrupt number as function argument and
 * hence we hand-roll what the "INT" instruction would do.
 *
 * [1] https://www.felixcloutier.com/x86/intn:into:int3:int1
 */

/* Segment selector chosen according to gdt in mbr.S */

.code32
.global bios_call
bios_call:
    /* Save all general purpose registers on the stack..
     *     eax
     *     ecx
     *     edx
     *     ebx
     *     esp (original value at pushad)
     *     ebp
     *     esi
     *     edi <- esp after instruction
     */
    pushad

    // Load 16-bit protected mode cs.
    jmp 0x18:pm16
.code16
pm16:
    // Disable protected mode.
    mov eax, cr0
    and eax, ~(1 << 0)
    mov cr0, eax

    // Load real mode cs. In real mode segment register are used for
    // segmented addressing, and dont reference gdt entries.
    jmp 0x0:1f
1:
    // Load real mode segment selectors.
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax

    /* Fetch function arguments, at this point the stack looks as
     *     arg1                   | esp + 10 * 4
     *     arg0                   | esp +  9 * 4
     *     return addr            | 1 * 4 bytes
     *     pushad frame  <- esp   | 8 * 4 bytes
     */
    movzx ebx, byte ptr  [esp + 4 *  9]    // arg0 (interrupt)
    mov   eax, dword ptr [esp + 4 * 10]    // arg1 (register)

    /* Hand-roll "INT n" to invoke the bios call.
     *
     * From the instruction manual [1]
     *   The action of the INT n instruction is similar to that of a
     *   far call made with the CALL instruction. The primary
     *   difference is that with the INT n instruction, the EFLAGS
     *   register is pushed onto the stack before the return
     *   address. (The return address is a far address consisting of
     *   the current values of the CS and EIP registers.) Returns from
     *   interrupt procedures are handled with the IRET [2]
     *   instruction, which pops the EFLAGS information and return
     *   address from the stack.
     *
     *   The vector specifies an interrupt descriptor in the interrupt
     *   descriptor table (IDT); that is, it provides index into the
     *   IDT. The selected interrupt descriptor in turn contains a
     *   pointer to an interrupt or exception handler procedure [..]
     *   In real-address mode, the IDT is an array of 4-byte far
     *   pointers (2-byte code segment selector and a 2-byte
     *   instruction pointer), each of which point directly to a
     *   procedure in the selected segment. (Note that in real-address
     *   mode, the IDT is called the interrupt vector table, and its
     *   pointers are called interrupt vectors.)
     *
     * IVT entry [3]
     *   +-----------+-----------+
     *   |  Segment  |  Offset   |
     *   +-----------+-----------+
     *   4           2           0
     *
     * [1] https://www.felixcloutier.com/x86/intn:into:int3:int1
     * [2] https://www.felixcloutier.com/x86/iret:iretd:iretq
     * [3] https://wiki.osdev.org/Interrupt_Vector_Table
     */

    // Setup interrupt frame, which the bios interrupt will return
    // from using an IRETW as described above.
    pushfw
    push cs
    push offset bcret

    // Setup interrupt frame to perform a far jump to the bios
    // interrupt handler. The IVT resides at address 0, hence we can
    // load the 'seg' and 'off (ip)' from the IVT entry based on the
    // user provided interrupt number (bx).
    //
    // We use an interrupt frame + IRETW as "jmp seg:off" needs an
    // assembly time known segment.
    pushfw
    push word ptr [4 * ebx + 2]
    push word ptr [4 * ebx + 0]

    // Load register state for the bios call from the register pointer
    // passed as function argument.
    mov ebx, [eax + EBX_OFFSET]
    mov eax, [eax + EAX_OFFSET]

    // Invoke bios interrupt.
    // This pops 3 words from the stack, first is the new IP, next the
    // new CS and the last are the new FLAGS.
    iretw
bcret:
    // Push register to stack to update register state function argument.
    push eax
    push ebx

    // Fetch function argument (arg1) for register state pointer.
    // Offset adjusted for two registers pushed just above.
    mov  eax, dword ptr [esp + 4 * 10 + 4 * 2]

    // Update register state structure.
    pop dword ptr [eax + EBX_OFFSET]
    pop dword ptr [eax + EAX_OFFSET]

    // Enable protected mode.
    mov eax, cr0
    or  eax, (1 << 0)
    mov cr0, eax

    // Load 32-bit protected mode cs.
    jmp 0x8:bcret32
.code32
bcret32:
    // Load 32-bit protected mode segment selectors.
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax

    // Restore all general purpose register.
    popad

    ret
