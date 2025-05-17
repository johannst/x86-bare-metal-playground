// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>
//
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
// E820 entry
//   base: u64,
//   size: u64,
//   kind: u32,
//   attr: u32, // ACPI 3.0 compat
//
// [1] https://wiki.osdev.org/Memory_Map_(x86)

.code16

.text
.global _entry
_entry:
        cli

        xor %ax, %ax
        mov %ax, %ds
        mov %ax, %es
        mov %ax, %ss
        mov %ax, %fs
        mov %ax, %gs

        // Far jump, load 0x0 into cs.
        ljmp $0x0, $rm16
rm16:
        // Setup stack pointer.
        mov $_stack_top, %esp

        /**
         * Make bios calls to fetch the e820 entries and store them at the
         * memory location marked in the linker script. Each time the bios call
         * is made it returns on e820 entry and returns an continuation code in
         * ebx. One needs to keep issuing the bios calls to iterated the entries.
         *
         * This should also do some bound check before storing, but we assume
         * that we have enough space for this example :^).
         */

e820start:
        // Get pointer to e820 entry counter (u64*).
        mov $_e820_start + 0, %si  // pointer to entry counter (u64*)
        // Get pointer to first e820 entry (e820*).
        mov $_e820_start + 8, %di
        // Load b"SMAP" magic string.
        mov $0x534D4150, %edx
        // Continuation code, start with first e820 memap entry.
        mov $0, %bx
e820:
        // Load bios call number.
        mov $0xe820, %ax
        // Load size of e820 entry.
        mov $24, %cx
        // BIOS call.
        int $0x15
        jc err

        // Advance pointer to next e820 entry.
        add $24, %di
        // Increment entry counter.
        incb (%si)
        // Check if continuation code is back to 0, and if so stop iterating.
        test %bx, %bx
        jnz e820

        /**
         * Walk the stored e820 entries and fmt print them to serial.
         */

        // Load number of e820 entries.
        mov _e820_start, %ecx
        // Get pointer to first e820 entry.
        mov $_e820_start + 8, %bx
1:
        // Print lower 32bit of e820.base address.
        mov (%bx), %eax
        call hexfmt
        mov %di, %si
        call puts

        // Prunt delimiter.
        mov $'-', %al
        call putc

        // Compute and print lower 32bit of (e820.base + e820.size - 1).
        mov (%bx), %eax
        add 8(%bx), %eax
        dec %eax
        call hexfmt
        mov %di, %si
        call puts

        // Prunt newline.
        mov $'\n', %al
        call putc
        mov $'\r', %al
        call putc

        // Advance pointer to next e820 entry.
        add $24, %bx

        // Decrement ecx and keep looping while ecx != 0.
        loop 1b

        // Halt program.
1:
        hlt
        jmp 1b
err:
        mov $'E', %al
        call putc
        hlt

/**
 * BIOS text mode call - print character to screen.
 * Input: %al
 * Clobber: %al
 */
putc:
        mov $0xe, %ah          // BIOS teletype function (to print characters)
        int $0x10              // Print character via BIOS interrupt
        ret

/**
 * Print null-terminated string to screen.
 */
puts:
        mov (%si), %al          // Load character to AL
        cmp $0, %al             // If it is null terminator, we're done
        je 1f
        call putc
        inc %si                // Move to the next character
        jmp puts
1:
        ret

/**
 * Format number as dec string.
 * Input : %eax (number to format)
 * Output: %edi (pointer to global string buffer with hex formatted number)
 * Clobber: %ecx, %edx
 *
 * This effectively implements the following function.
 *
 *   static char buf[16];
 *
 *   char* decfmt(unsigned num) {
 *       char* p = buf + sizeof(buf) - 1;
 *       do {
 *           unsigned mod = num % 10;
 *           *(--p) = '0' + mod;
 *           num /= 10;
 *       } while (num);
 *       return p;
 *   }
 */
decfmt:
        // Get pointer to the end of the buffer (output pointer).
        mov $buf + (bufend - buf) -1, %edi
        // Place divisor in register (no imm divisor operand).
        mov $10, %ecx
1:
        // Move output pointer.
        dec %edi
        // Clear upper half of dividend.
        xor %edx, %edx
        // Unsigned division %edx:%eax / %ecx -> %eax:quotient; %edx:remainder
        div %ecx
        // Remainder to ascii character.
        add $'0', %edx
        // Store character in output array.
        mov %dl, (%edi)
        // Check if the quotient is 0 and stop if so.
        cmp $0, %eax
        jnz 1b
        ret

/**
 * Format number as hex string.
 * Input : %eax (number to format)
 * Output: %edi (pointer to global string buffer with hex formatted number)
 * Clobber: %edx
 *
 * This effectively implements the following function.
 *
 *   static char buf[16];
 *
 *   char* hexfmt(unsigned num) {
 *       const char hex[] = "0123456789abcdef";
 *       char* p = buf + sizeof(buf) - 1;
 *       do {
 *           unsigned mod = num & 0xf;
 *           *(--p) = hex[mod];
 *           num >>= 4;
 *       } while (num);
 *       return p;
 *   }
 */
hexfmt:
        // Get pointer to the end of the buffer (output pointer).
        mov $buf + (bufend - buf) - 1, %edi
1:
        // Move output pointer.
        dec %edi
        // Copy quotient and compute remainder.
        mov %eax, %edx
        and $0xf, %edx
        // Divide quotient by 16.
        shr $4, %eax
        // Load ascii character for remainder.
        movb hex(%edx), %dl
        // Store character in output array.
        movb %dl, (%edi)
        // Check if the quotient is 0 and stop if so.
        cmp $0, %eax
        jnz 1b
        ret
// Hex to ascii lookup table.
hex:
.ascii "0123456789abcdef"

// Static string buffer.
buf:
.fill 16, 1, 0x00
bufend:

// MBR magic.
.fill 510 - (. - _entry), 1, 0x00
.byte 0x55, 0xaa


