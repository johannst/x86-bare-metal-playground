// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

const std = @import("std");

const ForegroundColor = enum(u4) {
    black = 0,
    blue,
    green,
    cyan,
    red,
    magenta,
    brown,
    light_gray,
    dark_gray,
    light_blue,
    light_green,
    light_cyan,
    light_red,
    pink,
    yellow,
    white,
};
const BackgroundColor = enum(u3) {
    black = 0,
    blue,
    green,
    cyan,
    red,
    magenta,
    brown,
    light_gray,
};

/// VGA text mode console [1]
///
/// 8 colors + 8 bright variants:
///   - 0x0  black      (0x8  dark gray)
///   - 0x1  blue       (0x9  light blue)
///   - 0x2  green      (0xa  light green)
///   - 0x3  cyan       (0xb  light cyan)
///   - 0x4  red        (0xc  light red)
///   - 0x5  magenta    (0xd  pink)
///   - 0x6  brown      (0xe  yellow)
///   - 0x7  light gray (0xf  white)
///
/// [1] https://en.wikipedia.org/wiki/VGA_text_mode
pub fn vga(fg: ForegroundColor, bg: BackgroundColor) type {
    return struct {
        const Self = @This();

        // Text mode dimensions (mode 3h text mode 80x25).
        const COLS = 80;
        const ROWS = 25;
        // Slice into VGA video memory.
        const VIDEO: []u16 = @as([*]u16, @ptrFromInt(0xB8000))[0 .. COLS * ROWS];

        /// Current index into last line.
        col: usize,

        /// Default value.
        pub const init: Self = .{
            .col = 0,
        };

        /// Write string to screen and move cursor.
        pub fn puts(self: *Self, msg: []const u8) void {
            for (msg) |char| {
                self.putcImpl(char);
            }
            self.updateCursor();
        }

        /// Write character to screen and move cursor.
        pub fn putc(self: *Self, char: u8) void {
            self.putcImpl(char);
            self.updateCursor();
        }

        /// Write character to screen.
        fn putcImpl(self: *Self, char: u8) void {
            if (char == '\n') {
                self.lf();
                return;
            }

            const idx = (ROWS - 1) * COLS + self.col;
            VIDEO[idx] = vgaEntry(char, fg, bg);

            self.col += 1;
            if (self.col == COLS) {
                self.lf();
            }
        }

        /// Handle linefeed (newline).
        /// Move up all lines by one, shifting out the upper most line.
        fn lf(self: *Self) void {
            // Shift all rows one up, copy rows [1. ROWS[-> [0, ROWS-1[.
            for (0..(ROWS - 1) * COLS) |idx| {
                VIDEO[idx] = VIDEO[1 * COLS + idx];
            }
            // Clear ROWS-1 (last row).
            for (0..COLS) |idx| {
                VIDEO[(ROWS - 1) * COLS + idx] = vgaEntry(' ', fg, bg);
            }
            self.col = 0;
        }

        /// Update cursor to current position.
        /// https://wiki.osdev.org/Text_Mode_Cursor#Without_the_BIOS
        fn updateCursor(self: Self) void {
            const idx = (ROWS - 1) * COLS + self.col;

            outb(0x3d4, 0xf);
            outb(0x3d5, @truncate(idx & 0xff));
            outb(0x3d4, 0xe);
            outb(0x3d5, @truncate(idx >> 8 & 0xff));
        }

        pub fn writer(self: *Self, buffer: []u8) VgaWriter {
            return .{
                .ctx = self,
                .interface = .{ .buffer = buffer, .vtable = &.{ .drain = VgaWriter.drain } },
            };
        }

        pub const VgaWriter = struct {
            ctx: *Self,
            interface: std.Io.Writer,

            fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.io.Writer.Error!usize {
                if (splat > 1) return error.WriteFailed;

                // Get pointer to VgaWriter container.
                const vw: *@This() = @alignCast(@fieldParentPtr("interface", w));

                // Consume buffered data.
                var count = w.buffered().len;
                if (count > 0) {
                    vw.ctx.puts(w.buffered());
                }

                // Consume additional data.
                for (data) |slice| {
                    count += slice.len;
                    vw.ctx.puts(slice);
                }

                return w.consume(count);
            }

            pub fn print(w: *VgaWriter, comptime fmt: []const u8, args: anytype) void {
                w.interface.print(fmt, args) catch {};
            }

            pub fn flush(w: *VgaWriter) void {
                w.interface.flush() catch {};
            }
        };
    };
}

// Each VGA (text mode) video buffer entry is 16bit wide.
//      [15] blink
//   [14:12] bg color (3 bit)
//   [11: 8] fg color (4 bit)
//   [ 7: 0] ascii character
//
// https://en.wikipedia.org/wiki/VGA_text_mode
inline fn vgaEntry(char: u8, fg: ForegroundColor, bg: BackgroundColor) u16 {
    return @as(u16, @intFromEnum(bg)) << 12 | @as(u16, @intFromEnum(fg)) << 8 | char;
}

inline fn outb(port: u16, val: u8) void {
    _ = asm volatile ("outb %[al], %[dx]"
        : // no outputs
        : [al] "{al}" (val),
          [dx] "{dx}" (port),
    );
}
