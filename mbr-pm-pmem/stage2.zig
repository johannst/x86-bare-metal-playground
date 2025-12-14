// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

const std = @import("std");
const com = @import("shared/com.zig");
const vga = @import("shared/vga.zig");
const rs = @import("shared/rangeset.zig");
const bios = @import("bios_call.zig");

const E820Kind = enum(u32) {
    free = 0x1,
    used = 0x2,
    acpi_tables = 0x3,
    acpi_nvs = 0x4,
};

const E820Magic: u32 = std.mem.readInt(u32, "SMAP", .big);

const E820 = extern struct {
    base: u64 = 0,
    size: u64 = 0,
    kind: E820Kind = .free,
    attr: u32 = 1, // ACPI 3.0 compat

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("E820: {x:08}-{x:08} {}", .{ self.base, self.base + self.size - 1, self.kind });
    }
};

fn getFreePhysicalMemory(comptime N: u8) !rs.RangeSet(N) {
    var pmem = rs.RangeSet(N).init;
    // On the first run accumulate all free memory and on the second remove all used.
    // This is just defensive as some BIOSes may report used memory as free.
    for ([2]bool{ true, false }) |insert| {
        var regs = std.mem.zeroes(bios.RegisterState);
        while (true) {
            // E820 bios call to get system memory map.
            // http://www.ctyme.com/intr/rb-1741.htm
            var e820 = std.mem.zeroes(E820);
            regs.eax = 0xe820;
            regs.ecx = @sizeOf(E820);
            regs.edi = @intFromPtr(&e820);
            regs.edx = E820Magic;
            bios.bios_call(0x15, &regs);
            if (regs.cf())
                return error.FailedCarry;
            if (regs.eax != E820Magic)
                return error.FailedE820Magic;
            if (regs.ecx < 20)
                return error.FailedSize;

            if (insert and e820.kind == .free) {
                try pmem.insert(.{
                    .start = e820.base,
                    .end = e820.base + e820.size - 1,
                });
            } else if (!insert and e820.kind != .free) {
                try pmem.remove(.{
                    .start = e820.base,
                    .end = e820.base + e820.size - 1,
                });
            }

            // After the bios call, ebx will contain the continuation code or 0 when done.
            if (regs.ebx == 0) {
                break;
            }
        }
    }
    return pmem;
}

pub export fn stage2() void {
    var buf: [128]u8 = undefined;
    var com1 = com.Com.init(com.Com.COM1);
    var iow = com1.writer(&buf);
    //var vga1 = vga.vga(.light_green, .black).init;
    //var iow = vga1.writer(&buf);

    iow.putc('\n');

    var pmem = getFreePhysicalMemory(8) catch |err| {
        iow.print("getFreePhysicalMemory: {}\n", .{err});
        return;
    };
    // Remove first 1M.
    pmem.remove(.{ .start = 0x0, .end = 1024 * 1024 - 1 }) catch |err| {
        iow.print("remove first 1M failed: {}\n", .{err});
        return;
    };
    iow.print("Free physical memory\n{f}\n", .{pmem});

    // Print free memory.
    var free_mem: u64 = 0;
    for (pmem.ranges[0..pmem.used]) |r| {
        free_mem += r.end - r.start + 1;
    }
    iow.print("free mem {} ({}M)\n", .{ free_mem, free_mem / 1024 / 1024 });

    // Allocate some pages.
    for (0..5) |_| {
        iow.print("page {x}\n", .{pmem.alloc(4096, 4096).?});
    }

    // Print free memory.
    free_mem = 0;
    for (pmem.ranges[0..pmem.used]) |r| {
        free_mem += r.end - r.start + 1;
    }
    iow.print("free mem {} ({}M)\n", .{ free_mem, free_mem / 1024 / 1024 });

    iow.flush();
}
