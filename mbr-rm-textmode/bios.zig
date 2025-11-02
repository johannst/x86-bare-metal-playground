// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

/// BIOS starts with video mode 0h.
///   * 80x25 text mode
///   * 16 colors (4bit)
/// http://www.ctyme.com/intr/rb-0069.htm
pub const COLS = 80;
pub const ROWS = 25;

/// BIOS CALL - video teletype output.
/// http://www.ctyme.com/intr/rb-0106.htm
pub fn putc(c: u8) void {
    // ah=0eh (call nr)
    // al=c   (ascii char to write)
    const ax = (@as(u16, 0xe) << 8) | c;

    _ = asm volatile (
        \\int $0x10
        : // No outputs.
        : [a] "{ax}" (ax), // BIOS call number + char to write.
        : .{ .cc = true });

    // On linefeed also write a carriage return to move to column 0.
    if (c == '\n') {
        putc('\r');
    }
}

/// BIOS CALL - video set cursor position.
/// http://www.ctyme.com/intr/rb-0087.htm
pub fn set_pos(r: u8) void {
    // dh=r (cursor row)
    // dl=0 (cursor col)
    const dx = @as(u16, r) << 8 | 0;

    _ = asm volatile (
        \\int $0x10
        : // No outputs.
        : [a] "{ax}" (0x200), // BIOS call number.
          [b] "{bx}" (0x0), // Page number.
          [d] "{dx}" (dx), // Position.
        : .{ .cc = true });
}

/// BIOS CALL - video scroll up
/// http://www.ctyme.com/intr/rb-0096.htm
pub fn scroll_up() void {
    // ah=06h (call nr)
    // al=1   (rows to scroll)
    const ax = (@as(u16, 0x6) << 8) | 1;

    // dh=ROWS-1 (row lower right corner)
    // dl=COLS-1 (col lower right corner)
    const dx = (@as(u16, ROWS - 1) << 8) | (COLS - 1);

    _ = asm volatile (
        \\int $0x10
        : // No outputs.
        : [a] "{ax}" (ax), // BIOS call number + rows to scroll.
          [p] "{dx}" (dx), // Row + col lower right corner.
          [b] "{bx}" (0x0700), // Attribute, dark bg, white fg.
          [c] "{cx}" (0), // Row + col upper left corner.
        : .{ .cc = true });
}
