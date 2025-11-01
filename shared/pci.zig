// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

/// PCI configuration space header for a general PCI function (header.type 00h).
pub const ConfigSpaceHeader = extern struct {
    vendor_id: u16,
    device_id: u16,
    command: u16,
    status: u16,
    revision_id: u8,
    prog_if: u8,
    subclass: u8,
    class: u8,
    cacheline_sz: u8,
    latency_timer: u8,
    header: packed struct(u8) { type: u7, multi_function: bool },
    bist: u8,
    bar: [6]u32,
    cis_ptr: u32,
    subvendor_id: u16,
    subdevice_id: u16,
    rom_base_addr: u32,
    cap_ptr: u8,
    reserved0: [7]u8,
    interrupt_line: u8,
    interrupt_pin: u8,
    min_gnt: u8,
    max_lat: u8,
};

/// Base address register (bar) for a 32 bit IO or MMIO region.
pub const Bar = extern struct {
    const io_mask: u32 = 0xffff_fffc;
    const mmio_mask: u32 = 0xffff_fff0;

    reg: *volatile u32,

    pub fn is64(val: u32) bool {
        if (_io(val))
            return false;
        return ((val >> 1) & 0b11) == 0b10;
    }

    pub fn io(self: *const Bar) bool {
        return _io(self.reg.*);
    }

    pub fn base(self: *const Bar) u32 {
        const val = self.reg.*;
        return val & _mask(val);
    }

    pub fn size(self: *Bar) u32 {
        // Read old register value and restore on exit.
        const old = self.reg.*;
        defer self.reg.* = old;

        // PCI says: Write all ones and read register back.
        self.reg.* = 0xffffffff;
        var new = self.reg.*;

        // PCI says, upper 16 bits are ignored if the bar for I/O and bits 31:16
        // returned zero.
        // We do this by setting them to all ones before inverting them later.
        if (self.io() and (new >> 16) == 0) {
            new |= 0xffff_0000;
        }

        // PCI says: Size is computed by clearing encoding bits, inverting all
        // bits and adding one.
        return ~(new & _mask(new)) + 1;
    }

    fn _mask(val: u32) u32 {
        return if (_io(val)) io_mask else mmio_mask;
    }

    fn _io(val: u32) bool {
        return (val & 1) == 1;
    }
};

/// Base address register (bar) for a 64 bit MMIO region (no IO).
pub const Bar64 = extern struct {
    const mmio_mask: u64 = 0xffffffff_fffffff0;

    regl: *volatile u32,
    regh: *volatile u32,

    pub fn base(self: *const Bar64) u64 {
        const val = (@as(u64, self.regh.*) << 32) | self.regl.*;
        return val & mmio_mask;
    }

    pub fn size(self: *Bar64) u64 {
        // Read old register values and restore on exit.
        const oldh = self.regh.*;
        const oldl = self.regl.*;
        defer {
            self.regh.* = oldh;
            self.regl.* = oldl;
        }

        self.regh.* = 0xffffffff;
        self.regl.* = 0xffffffff;
        const new = (@as(u64, self.regh.*) << 32) | self.regl.*;

        return ~(new & mmio_mask) + 1;
    }
};

comptime {
    const assert = @import("std").debug.assert;

    // PCI values are little endian, only support little endian targets.
    assert(@import("builtin").target.cpu.arch.endian() == .little);

    assert(@sizeOf(ConfigSpaceHeader) == 0x40);
    assert(@offsetOf(ConfigSpaceHeader, "bar") == 0x10);
    assert(@offsetOf(ConfigSpaceHeader, "cap_ptr") == 0x34);
}
