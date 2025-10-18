// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

const std = @import("std");
const bios = @import("bios_call.zig");

/// A real mode segmented address.
const SegOff = extern struct {
    off: u16 = 0,
    seg: u16 = 0,
};

const DiskAddressPacket = extern struct {
    /// Size of this disk packet in bytes.
    pkt_size: u8 = @sizeOf(DiskAddressPacket),

    /// Reserved byte which should be zero.
    reserved: u8 = 0,

    /// Number of blocks to read in sectors (512 btyes).
    num_blks: u16,

    /// Destination address, where the read sectors should be written to.
    /// This is a real mode segmented address.
    dest_addr: SegOff,

    /// Block number (LBA) to start reading from (0 indexed, MBR is at 0).
    start_blk: u64,
};

// Start and end symbols of the stage2 bootloader (defined in the linker script).
extern const _stage2_start: u8;
extern const _stage2_end: u8;

/// Load stage2 bootloader from disk using the int=13h/ah=42h bios call.
///
/// Disk extended read (int 13h) [1].
///     ah = 42h
///     dl = drive number
///     ds:si = address of disk packet
/// Return
///     cf = 0 (success) 1 (failed)
///     ah = 0 (success) error code (failed)
///
/// [1] http://www.ctyme.com/intr/rb-0708.htm
/// [2] https://en.wikipedia.org/wiki/Logical_block_addressing
fn load_stage2(boot_disk: u32) !void {
    const dap = DiskAddressPacket{
        .num_blks = @truncate((&_stage2_end - &_stage2_start) / 512),
        .dest_addr = .{ .off = @truncate(@intFromPtr(&_stage2_start)) },
        .start_blk = 1,
    };

    var regs = std.mem.zeroes(bios.RegisterState);
    regs.eax = 0x42_00;
    regs.esi = @intFromPtr(&dap);
    regs.edx = boot_disk;

    bios.bios_call(0x13, &regs);

    // Quirk for bios on my old laptop, which keeps IF=1 after this bios call.
    asm volatile ("cli");

    // Check carry flag for success.
    if (regs.eflags & 1 != 0) {
        return error.FailedToLoadStage2;
    }
}

extern fn stage2_entry() void;
export fn stage1_entry(boot_disk: u32) void {
    if (load_stage2(boot_disk)) {
        stage2_entry();
    } else |_| {
        var regs = std.mem.zeroes(bios.RegisterState);
        regs.eax = @as(u32, 0xe00) | 'E';
        bios.bios_call(0x10, &regs);
    }
}
