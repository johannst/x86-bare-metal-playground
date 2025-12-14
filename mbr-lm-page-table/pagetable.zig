// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

const std = @import("std");

/// Physical address.
pub const PhysAddr = struct {
    val: u64,

    fn checkedAdd(self: *PhysAddr, addend: u64) !PhysAddr {
        const ov = @addWithOverflow(self.val, addend);
        return if (ov[1] == 0) .{ .val = ov[0] } else error.PhysAddrOverflow;
    }
};

/// Virtual address.
pub const VirtAddr = struct {
    val: u64,

    fn isCanonical(self: VirtAddr) bool {
        const ones = @popCount(self.val >> 48);
        return ones == 0 or ones == 16;
    }

    fn indices(self: VirtAddr) [4]u9 {
        return .{
            @truncate(self.val >> 39),
            @truncate(self.val >> 30),
            @truncate(self.val >> 21),
            @truncate(self.val >> 12),
        };
    }
};

/// Interface to access and allocate physical memory.
pub const PhysMem = struct {
    pub const TranslateError = error{
        PhysRangeUnmapped,
    };
    pub const AllocError = error{
        PhysOutOfMemory,
    };

    const VTable = struct {
        /// Translate a physical adress range to a virtual address,
        /// such that it can be read from or written to.
        translate: *const fn (*anyopaque, paddr: PhysAddr, len: usize) TranslateError!VirtAddr,
        /// Allocate size bytes out of physical memory with the given alignment requirements.
        alloc: *const fn (*anyopaque, size: usize, alignment: usize) AllocError!PhysAddr,
    };

    ctx: *anyopaque,
    vtable: *const VTable,

    fn readPhys(self: PhysMem, comptime T: type, paddr: PhysAddr) !T {
        comptime std.debug.assert(T == u64 or T == u32);
        const vaddr = try self.vtable.translate(self.ctx, paddr, @sizeOf(T));
        std.debug.assert(std.mem.isAligned(vaddr.val, @alignOf(T)));
        return @as(*T, @ptrFromInt(vaddr.val)).*;
    }

    fn writePhys(self: PhysMem, comptime T: type, paddr: PhysAddr, val: T) !void {
        comptime std.debug.assert(T == u64 or T == u32);
        const vaddr = try self.vtable.translate(self.ctx, paddr, @sizeOf(T));
        std.debug.assert(std.mem.isAligned(vaddr.val, @alignOf(T)));
        @as(*T, @ptrFromInt(vaddr.val)).* = val;
    }

    fn allocPageZeroed(self: PhysMem) !PhysAddr {
        const paddr = try self.vtable.alloc(self.ctx, 4096, 4096);
        const vaddr = try self.vtable.translate(self.ctx, paddr, 4096);
        std.debug.assert(std.mem.isAligned(vaddr.val, 4096));

        // Zero out page.
        const bytes = @as([*]u8, @ptrFromInt(vaddr.val))[0..4096];
        @memset(bytes, 0);

        return paddr;
    }
};

/// Mark page table entry as present.
const PAGE_PRESENT: u64 = 1 << 0;
/// Mark page table entry as write-able, such that write access to the page is allowed.
const PAGE_WRITE: u64 = 1 << 1;
/// Mark page table entry to map a large page (1G or 2M), only for PDPTE and PDE.
const PAGE_SIZE: u64 = 1 << 7;

/// Page table entry.
const Entry = struct {
    val: u64,

    fn present(self: Entry) bool {
        return self.val & PAGE_PRESENT != 0;
    }

    fn size(self: Entry) bool {
        return self.val & PAGE_SIZE != 0;
    }

    fn paddr(self: Entry) PhysAddr {
        return .{ .val = self.val & 0x000f_ffff_ffff_f000 };
    }

    pub fn format(self: Entry, io: *std.Io.Writer) !void {
        try io.print("PTE paddr={x:08} P={} PS={}", .{ self.paddr().val, self.present(), self.size() });
    }
};

/// Supported page sizes.
/// Support for 2M pages is mandatory for long-mode, 1G support is optional.
const PageSize = enum {
    page4k,
    page2M,

    fn value(self: PageSize) u64 {
        return switch (self) {
            .page4k => 4096,
            .page2M => 2 * 1024 * 1024,
        };
    }

    fn mask(self: PageSize) u64 {
        return self.value() - 1;
    }
};

/// Page table.
pub const PageTable = struct {
    root: PhysAddr,
    io: *std.Io.Writer,

    /// Create a new PageTable from the value in CR3 register.
    pub fn from_cr3(io: *std.Io.Writer) PageTable {
        return .{
            // Mask off potential PCID bits from cr3.
            .root = .{ .val = read_cr3() & ~@as(u64, 0xfff) },
            .io = io,
        };
    }

    /// Lookup virtual address and return page table entries for each level.
    /// Return an error if the virtual address is not mapped.
    pub fn lookup(self: PageTable, phys_mem: *const PhysMem, vaddr: VirtAddr) ![4]?Entry {
        if (!vaddr.isCanonical())
            return error.VirtAddrNotCanonical;

        var ptes: [4]?Entry = .{null} ** 4;

        var table = self.root;
        for (vaddr.indices(), 0..) |idx, depth| {
            const pte_addr = try table.checkedAdd(idx * @sizeOf(Entry));
            const pte = Entry{ .val = try phys_mem.readPhys(u64, pte_addr) };

            if (!pte.present())
                return error.VirtAddrNotMapped;

            ptes[depth] = pte;

            // If it is a 1G or 2M page end the lookup.
            switch (depth) {
                1, 2 => if (pte.size()) break,
                else => std.debug.assert(!pte.size()),
            }

            table = pte.paddr();
        }
        return ptes;
    }

    /// Map physical address PADDR at virtual address VADDR for page size PGSZ.
    /// Return an error if anything goes wrong. On error intermmediate page table entries are not cleaned up.
    pub fn map_phys(self: PageTable, phys_mem: *const PhysMem, vaddr: VirtAddr, pgsz: PageSize, paddr: PhysAddr) !void {
        if (!vaddr.isCanonical())
            return error.VirtAddrNotCanonical;
        if (vaddr.val & pgsz.mask() != 0)
            return error.VirtAddrMissAligned;
        if (paddr.val & pgsz.mask() != 0)
            return error.PhysAddrMissAligned;

        // Get indices for each page table level depending on the page size.
        const indices = switch (pgsz) {
            .page4k => vaddr.indices()[0..],
            .page2M => vaddr.indices()[0..3],
        };

        // Start reading entries from the root table.
        var table = self.root;

        for (indices, 0..) |idx, depth| {
            // Compute paddr of pte and read pte.
            const pte_addr = try table.checkedAdd(idx * @sizeOf(Entry));
            const pte = Entry{ .val = try phys_mem.readPhys(u64, pte_addr) };

            self.io.print("{}: PA:{x:08} -> PTE:{x:08}, ", .{ depth, pte_addr.val, pte.val }) catch {};

            // If entry is present and marks a large page, the requested virtual address is already in use.
            if (pte.present() and pte.size()) {
                std.debug.assert(depth == 1 or depth == 2);
                return error.VirtAddrAlreadyMapped;
            }

            switch (depth) {
                0...1 => {
                    if (pte.present()) {
                        table = pte.paddr();
                        self.io.print("next table PA:{x:08}\n", .{table.val}) catch {};
                    } else {
                        table = try phys_mem.allocPageZeroed();
                        try phys_mem.writePhys(u64, pte_addr, table.val | PAGE_WRITE | PAGE_PRESENT);
                        self.io.print("alloced new table PA:{x:08}\n", .{table.val}) catch {};
                    }
                },
                2 => {
                    if (pte.present()) {
                        if (pgsz == .page2M)
                            return error.VirtAddrAlreadyMapped;

                        table = pte.paddr();
                        self.io.print("next table PA:{x:08}\n", .{table.val}) catch {};
                    } else if (pgsz == .page2M) {
                        try phys_mem.writePhys(u64, pte_addr, paddr.val | PAGE_SIZE | PAGE_WRITE | PAGE_PRESENT);
                        self.io.print("mapped 2M page VA:{x:08} -> PA:{x:08}-{x:08}\n", .{ vaddr.val, paddr.val, paddr.val + pgsz.value() - 1 }) catch {};
                    } else {
                        table = try phys_mem.allocPageZeroed();
                        try phys_mem.writePhys(u64, pte_addr, table.val | PAGE_WRITE | PAGE_PRESENT);
                        self.io.print("alloced new table PA:{x:08}\n", .{table.val}) catch {};
                    }
                },
                3 => {
                    if (pte.present())
                        return error.VirtAddrAlreadyMapped;

                    try phys_mem.writePhys(u64, pte_addr, paddr.val | PAGE_WRITE | PAGE_PRESENT);
                    self.io.print("mapped 4k page VA:{x:08} -> PA:{x:08}-{x:08}\n", .{ vaddr.val, paddr.val, paddr.val + pgsz.value() - 1 }) catch {};
                },
                else => unreachable,
            }

            self.io.flush() catch {};
        }
    }
};

/// Inline assembly to read the CR3 register, which holds the pointer to the
/// first paging structure (plus some metadata bits).
inline fn read_cr3() u64 {
    return asm volatile (
        \\mov %%cr3, %[ret]
        : [ret] "=r" (-> u64),
    );
}
