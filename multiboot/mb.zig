// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

// Multiboot [1]
//
// * OS image requiremets
//   - 32 bit executable file
//   - multiboot header in the first 8192 bytes, and 4 byte aligned
//
// * Machine state
//  - eax: contains the magic value 0x2BADB002
//  - ebx: 32 bit phys addr of the multiboot info structure
//  - cs: 32 bit rx segment [0..0xffff_ffff]
//  - ds/es/fs/gs/ss: 32 bit rw segment [0..0xffff_ffff]
//  - a20 gate enabled [3]
//  - cr0: paging (PG) disabled, protection (PE) enabled
//  - esp: os must setup its own stack when it needs one
//  - gdtr/idtr: os image must setup own tables
//
// [1] https://www.gnu.org/software/grub/manual/multiboot/multiboot.html
// [2] https://www.gnu.org/software/grub/manual/multiboot/multiboot.pdf
// [3] https://wiki.osdev.org/A20_Line

// -- MULTIBOOT HEADER ----------------------------------------------------------

const MBH_MEMALIGN = (1 << 0);
const MBH_MEMINFO = (1 << 1);

const MAGIC = 0x1BADB002;
const FLAGS = MBH_MEMINFO;
const CHECKSUM: i32 = -MAGIC - FLAGS;

const MultibootHeader = extern struct {
    magic: u32,
    flags: u32,
    checksum: i32,
};

pub const HEADER = MultibootHeader{
    .magic = MAGIC,
    .flags = FLAGS,
    .checksum = CHECKSUM,
};

// -- MULTIBOOT INFO ------------------------------------------------------------

const MultibootInfoFlag = enum(u32) {
    MEMORY = (1 << 0),
    BOOTDEV = (1 << 1),
    CMDLINE = (1 << 2),
    MODS = (1 << 3),
    SYMAOUT = (1 << 4),
    SYMELF = (1 << 5),
    MEMMAP = (1 << 6),
    DRIVE = (1 << 7),
    CONFIG = (1 << 8),
    BOOTLOADER = (1 << 9),
    APM = (1 << 10),
    VBE = (1 << 11),
    FRAMEBUFFER = (1 << 12),
};

pub const MultibootInfo = extern struct {
    flags: u32,

    // Valid iff MEMORY flag set.
    mem_lower: u32,
    mem_upper: u32,

    // Valid iff BOOTDEV flag set.
    boot_device: u32,

    // Valid iff CMDLINE flag set.
    cmdline: u32,

    // Valid iff MODS flag set.
    mods_count: u32,
    mods_addr: u32,

    // Valid iff SYMAOUT or SYMELF flag set.
    _sym_stub: [4]u32,

    // Valid iff MEMMAP flag set.
    mmap_length: u32,
    mmap_addr: u32,

    // Valid iff DRIVE flag set.
    drives_length: u32,
    drives_addr: u32,

    // Valid iff CONFIG flag set.
    config_table: u32,

    // Valid iff BOOTLOADER flag set.
    boot_loader_name: u32,

    // Valid iff APM flag set.
    apm_table: u32,

    // Valid iff VBE flag set.
    vbe_control_info: u32,
    vbe_mode_info: u32,
    vbe_mode: u16,
    vbe_interface_seg: u16,
    vbe_interface_off: u16,
    vbe_interface_len: u16,

    // Valid iff FB flag set.
    framebuffer_addr: u64,
    framebuffer_pitch: u32,
    framebuffer_width: u32,
    framebuffer_height: u32,
    framebuffer_bpp: u8,
    framebuffer_type: u8,
    _framebuffer_palette_stub: [6]u8,

    /// Check if given multiboot info flag is set.
    fn has(self: @This(), flag: MultibootInfoFlag) bool {
        return (self.flags & @intFromEnum(flag)) != 0;
    }

    /// If the cmdline is available return a null-terminated c string.
    fn cmdlineStr(self: @This()) ?[*:0]const u8 {
        return if (self.has(.CMDLINE)) cstr(self.cmdline) else null;
    }

    /// If the bootloader name is available return a null-terminated c string.
    fn bootloaderStr(self: @This()) ?[*:0]const u8 {
        return if (self.has(.BOOTLOADER)) cstr(self.boot_loader_name) else null;
    }

    /// If the mmap info is available, return an iterator over the mmap entries.
    fn mmapIter(self: @This()) ?MultibootMmapEntry.Iter {
        return if (self.has(.MEMMAP)) .{ .addr = self.mmap_addr, .len = self.mmap_length, .off = 0 } else null;
    }
};

// This structure is defined as packed structure in the mb spec.
pub const MultibootMmapEntry = extern struct {
    size: u32 align(1),
    addr: u64 align(1),
    len: u64 align(1),
    type: u32 align(1),

    /// Get the `actual` size of an mmap entry.
    fn getSize(self: @This()) usize {
        // The `size` field expresses the actual size of the mmap structure
        // (w/o the size field).
        // The actual size can be larger as the struct definition.
        return self.size + @sizeOf(@TypeOf(self.size));
    }

    /// Get the mmap type as string.
    fn typeStr(self: @This()) []const u8 {
        return switch (self.type) {
            1 => "available",
            2 => "reserved",
            3 => "acpi-reclaim",
            4 => "nvs",
            5 => "badram",
            else => "<unknown>",
        };
    }

    /// Iterator type over mmap entries.
    const Iter = struct {
        addr: u32,
        len: u32,
        off: u32,

        /// Return the next mmap entry if the iterator is not exhausted.
        fn next(self: *@This()) ?*const MultibootMmapEntry {
            return if ((self.off + @sizeOf(MultibootMmapEntry)) > self.len)
                null
            else blk: {
                const m: *const MultibootMmapEntry = @ptrFromInt(self.addr + self.off);
                self.off += m.getSize();
                break :blk m;
            };
        }
    };
};

// -- MULTIBOOT UTILS -----------------------------------------------------------

const format = @import("std").fmt.format;

pub fn bootinfo(ebx: u32) *const MultibootInfo {
    return @ptrFromInt(ebx);
}

pub fn formatBootinfo(w: anytype, mbi: *const MultibootInfo) !void {
    try w.writeAll("multiboot info\n");

    try format(w, "flags: 0b{b}\n", .{mbi.flags});

    if (mbi.bootloaderStr()) |bootloader| {
        try format(w, "bootloader: {s}\n", .{bootloader});
    }

    if (mbi.cmdlineStr()) |cmdline| {
        try format(w, "cmdline: {s}\n", .{cmdline});
    }

    if (mbi.has(.MEMORY)) {
        try format(w, "mem_lower: {x:08} - {x:08}\n", .{ 0, mbi.mem_lower * 1024 });
        try format(w, "mem_upper: {x:08} - {x:08}\n", .{ 1024 * 1024, mbi.mem_upper * 1024 });
    }

    if (mbi.mmapIter()) |iter| {
        // Rebind iter,  cant bind mutable reference to temporary object.
        var it = iter;

        try format(w, "mmap: @ {x:08} - {x:08}\n", .{ it.addr, it.addr + it.len - 1 });
        while (it.next()) |map| {
            try format(w, "region: {x:08} - {x:08} | {s}\n", .{ map.addr, map.addr + map.len - 1, map.typeStr() });
        }
    }
}

fn cstr(addr: u32) [*:0]const u8 {
    return @ptrFromInt(addr);
}
