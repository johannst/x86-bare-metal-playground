// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

const com = @import("shared/com.zig");
const vga = @import("shared/vga.zig");
const rs = @import("shared/rangeset.zig");
const pt = @import("pagetable.zig");

const E820Kind = enum(u32) {
    free = 0x1,
    used = 0x2,
    acpi_tables = 0x3,
    acpi_nvs = 0x4,
};

const E820 = extern struct {
    base: u64 = 0,
    size: u64 = 0,
    kind: E820Kind = .free,
    attr: u32 = 1, // ACPI 3.0 compat
};

/// Physical memory implementation based on the MBRs idendity mapping.
const PhyicalMemory = struct {
    pmem: rs.RangeSet(8),

    fn translate(ctx: *anyopaque, paddr: pt.PhysAddr, len: usize) !pt.VirtAddr {
        _ = ctx;

        // MBR idendity maps the first 1G, see mbr.S:setup_page_table.
        const PHYS_WINDOW_END = 1024 * 1024 * 1024;

        if (paddr.val + len >= PHYS_WINDOW_END)
            return pt.PhysMem.TranslateError.PhysRangeUnmapped;

        return .{ .val = paddr.val };
    }

    fn alloc(ctx: *anyopaque, size: usize, alignment: usize) !pt.PhysAddr {
        const self: *PhyicalMemory = @ptrCast(@alignCast(ctx));
        const paddr = self.pmem.alloc(size, alignment) orelse return pt.PhysMem.AllocError.PhysOutOfMemory;
        return .{ .val = paddr };
    }

    fn physMem(self: *PhyicalMemory) pt.PhysMem {
        return .{
            .ctx = self,
            .vtable = &.{
                .translate = translate,
                .alloc = alloc,
            },
        };
    }
};

export fn main() void {
    var buf: [128]u8 = undefined;
    var vga1 = vga.vga(.light_green, .black).init;
    var iow = vga1.writer(&buf);
    //var com1 = com.Com.init(com.Com.COM1);
    //var iow = com1.writer(&buf);

    // Collect physical memory.
    var pmem = out: {
        const e820_cnt: *const u8 = @ptrFromInt(0x500);
        const e820_vec = @as([*]E820, @ptrFromInt(0x508))[0..e820_cnt.*];
        iow.print("found {} e820 entries\n", .{e820_cnt.*});

        var pmem = rs.RangeSet(8).init;
        for (e820_vec) |e820| {
            if (e820.kind == .free)
                pmem.insert(.{ .start = e820.base, .end = e820.base + e820.size - 1 }) catch {};
        }
        for (e820_vec) |e820| {
            if (e820.kind != .free)
                pmem.remove(.{ .start = e820.base, .end = e820.base + e820.size - 1 }) catch {};
        }
        iow.print("{f}\n", .{pmem});

        // Remove the first MB, which is used by the bios and our code.
        pmem.remove(.{ .start = 0, .end = 1024 * 1024 }) catch {};

        break :out PhyicalMemory{ .pmem = pmem };
    };

    const ptable = pt.PageTable.from_cr3(&iow.interface);

    // Try to map first 4k page of the VGA area into virtual address range.
    ptable.map_phys(
        &pmem.physMem(),
        pt.VirtAddr{ .val = 0x4000_0000 },
        .page4k,
        pt.PhysAddr{ .val = 0xb8000 },
    ) catch |e| {
        iow.print("pt.map error {}\n", .{e});
        iow.flush();
        return;
    };

    // Try to map first 2M of physical memory into virtual address range.
    // This also covers VGA area.
    ptable.map_phys(
        &pmem.physMem(),
        pt.VirtAddr{ .val = 0x8000_0000 },
        .page2M,
        pt.PhysAddr{ .val = 0x0 },
    ) catch |e| {
        iow.print("pt.map error {}\n", .{e});
        iow.flush();
        return;
    };

    // Write to VGA area through 4k mapping.
    @as(*u16, @ptrFromInt(0x4000_0000)).* = 0xc00 | '4';
    @as(*u16, @ptrFromInt(0x4000_0002)).* = 0xc00 | 'k';

    // Write to VGA area through 2M mapping.
    @as(*u16, @ptrFromInt(0x800b_8006)).* = 0xc00 | '2';
    @as(*u16, @ptrFromInt(0x800b_8008)).* = 0xc00 | 'M';

    iow.flush();
}
