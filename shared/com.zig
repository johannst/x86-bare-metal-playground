// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

// COM serial port driver [1] for the 8250 uart [3].
//
// COM ports are accessed via IO ports. Each port exposes a set of 1 byte
// registers relative to the ports base address.
//   0   Receive buffer (inb).
//   0   Transmit buffer (outb).
//   1   Interrupt enable.
//   2   Interrupt identification.
//   3   Line control.
//   4   Modem control.
//   5   Line status.
//   6   Modem status.
//   7   Scratch register.
//
// If DLAB bit in the line control register is '1', then offset 0/1 are
// remapped, to setup a 2 byte divisor value.
//   0   Low byte of the divisor.
//   1   High byte of the divisor.
// The COM port has an internal clock at 115200 Hz.
//
// The bios data area (DBA) may provide the base address of COM1-COM4 ports [2].
// The first two ports have fairly standardized base addresses
//   - COM1 0x3f8
//   - COM2 0x2f8
//
// [1] https://wiki.osdev.org/Serial_Ports
// [2] https://wiki.osdev.org/Memory_Map_(x86)
// [3] https://en.wikipedia.org/wiki/8250_UART

const std = @import("std");

// COM port register offsets relative to COM port base address.
const REG_DATA: u16 = 0;
const REG_INTR_EN: u16 = 1;
const REG_LINE_CTRL: u16 = 3;
const REG_LINE_STAT: u16 = 5;
// Remapped iff LINE_CTRL.DLAB == 1.
const REG_DIVLO: u16 = 0;
const REG_DIVHI: u16 = 1;

// Bit masks for LINE_CTRL register.
const BIT_DLAB: u8 = (1 << 7);

// Bit masks for LINE_STAT register.
const BIT_RX_READY: u8 = (1 << 0);
const BIT_TX_READY: u8 = (1 << 5);

/// Type to interact with x86 serial COM ports [1].
///
/// [1] https://wiki.osdev.org/Serial_Ports
pub const Com = struct {
    // Widely standardized address for COM1 port (eg also in qemu).
    pub const COM1: u16 = 0x3f8;

    base: u16,

    /// Initialize COM port at `base` address, with following configuration
    ///   - all interrupts disabled (polling)
    ///   - divisor = 1 (-> baud rate 115200)
    ///   - 8 data, 1 stop, no parity bits (8N1)
    pub fn init(base: u16) Com {
        // Disable all COM port interrupts.
        outb(base + REG_INTR_EN, 0);

        // Set DLAB bit, to enable access to divisor registers.
        outb(base + REG_LINE_CTRL, BIT_DLAB);

        // Set divisor=1, configuring a baud rate of 115200.
        outb(base + REG_DIVLO, 1);
        outb(base + REG_DIVHI, 0);

        // Unset DLAB bit, no parity, 1 stop bit, 8 data bits (8n1).
        outb(base + REG_LINE_CTRL, 0b11);

        return .{ .base = base };
    }

    /// Write out `msg` to COM port.
    pub fn puts(self: Com, msg: []const u8) void {
        for (msg) |ch| {
            self.putc(ch);
        }
    }

    /// Write out `char` to COM port.
    pub fn putc(self: Com, char: u8) void {
        while ((inb(self.base + REG_LINE_STAT) & BIT_TX_READY) == 0) {}
        outb(self.base, char);
    }

    pub fn writer(self: *Com, buffer: []u8) Writer {
        return .{
            .com = self,
            .interface = .{ .buffer = buffer, .vtable = &.{ .drain = Writer.drain } },
        };
    }
};

const Writer = struct {
    interface: std.Io.Writer,
    com: *Com,

    fn drain(iow: *std.Io.Writer, data: []const []const u8, splat: usize) !usize {
        if (splat > 1) return error.WriteFailed;
        const w: *Writer = @alignCast(@fieldParentPtr("interface", iow));

        // Consume buffered data.
        var count = iow.buffered().len;
        if (count > 0) {
            w.com.puts(iow.buffered());
        }

        // Consume additional data.
        for (data) |slice| {
            count += slice.len;
            w.com.puts(slice);
        }

        return iow.consume(count);
    }

    pub fn print(w: *Writer, comptime fmt: []const u8, args: anytype) void {
        w.interface.print(fmt, args) catch {};
    }

    pub fn flush(w: *Writer) void {
        w.interface.flush() catch {};
    }
};

// -- UTILS ---------------------------------------------------------------------

inline fn outb(port: u16, val: u8) void {
    _ = asm volatile ("outb %[al], %[dx]"
        : // No outputs.
        : [al] "{al}" (val),
          [dx] "{dx}" (port),
    );
}

inline fn inb(port: u16) u8 {
    var val: u8 = 0;
    _ = asm volatile ("inb %[dx], %[al]"
        : [al] "={al}" (val),
        : [dx] "{dx}" (port),
    );
    return val;
}
