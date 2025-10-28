// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

const std = @import("std");

/// Root System Description Pointer.
pub const Rsdp = extern struct {
    /// "RSD PTR" magic value.
    signature: [8]u8,
    /// ACPI 1.0 struct checksum, first 20 bytes must sum to zero.
    checksum: u8,
    /// Oem identifier.
    oem_id: [6]u8,
    /// ACPI version.
    /// 0 -> ACPI 1.0
    /// 2 -> ACPI 2.0+
    revision: u8,
    /// Physical address of RSDT (APCI 1.0).
    rsdt_addr: u32,

    // The following fields are only valid from ACPI 2.0 on.

    /// (ACPI 2.0) Length of the table in bytes, including rsdp.
    length: u32,
    /// (ACPI 2.0) Physical address of XSDT.
    xsdt_addr: u64,
    /// (ACPI 2.0) Checksum of entire table. Sum of all bytes must be zero.
    extended_checksum: u8,
    /// (ACPI 2.0) Reserved field.
    _reserved: [3]u8,

    pub fn validSignature(self: *const Rsdp) bool {
        return std.mem.eql(u8, &self.signature, "RSD PTR ");
    }

    pub fn validChecksum(self: *const Rsdp) bool {
        const length = switch (self.revision) {
            0 => @offsetOf(Rsdp, "length"),
            2 => self.length,
            else => return false,
        };

        var sum: u8 = 0;
        for (@as([*]const u8, @ptrCast(self))[0..length]) |byte| {
            sum +%= byte;
        }
        return sum == 0;
    }
};

/// System Description Table Header.
pub const Header = extern struct {
    /// Descripttor table identifier.
    signature: [4]u8,
    /// Length of the descriptor table in bytes including this header.
    length: u32,
    /// Revision of the descriptor table.
    revision: u8,
    /// Checksum of entire table. Sum of all bytes must be zero.
    checksum: u8,
    /// Oem identifier.
    oem_id: [6]u8,
    /// Oem table identifier.
    oem_tbl_id: [8]u8,
    /// Oem table revision.
    oem_revision: u32,
    /// Vendor identifier.
    creator_id: u32,
    /// Vendor revision.
    creator_revision: u32,

    pub fn validSignature(self: *const Header, expected: [4]u8) bool {
        return std.mem.eql(u8, &self.signature, &expected);
    }

    pub fn validChecksum(self: *const Header) bool {
        var sum: u8 = 0;
        for (@as([*]const u8, @ptrCast(self))[0..self.length]) |byte| {
            sum +%= byte;
        }
        return sum == 0;
    }

    pub fn payload(self: *const Header) ?[]const u8 {
        if (self.length <= @sizeOf(Header))
            return null;
        return @as([*]const u8, @ptrCast(self))[@sizeOf(Header)..self.length];
    }
};

/// Multiple APIC Description Table.
pub const Madt = extern struct {
    hdr: Header,
    /// Physical address of core local APIC.
    lapic_paddr: u32,
    /// APIC flags.
    lapic_flags: packed struct(u32) {
        dual_8259: u1,
        reserved: u31,
    },

    pub fn payload(self: *const Madt) ?[]const u8 {
        const p = self.hdr.payload() orelse return null;
        // Re-slice additional madt fields..
        return p[@sizeOf(Madt) - @sizeOf(Header) ..];
    }

    /// Common header for each interrupt controller.
    pub const IrqHeader = extern struct {
        kind: u8,
        length: u8,
    };

    /// Interrupt controller structure.
    pub const IrqCtrlStruct = union(enum) {
        lapic: *const extern struct {
            hdr: IrqHeader,
            uid: u8,
            id: u8,
            flags: u32,
        },
        io_apic: *const extern struct {
            hdr: IrqHeader,
            id: u8,
            reserved: u8,
            paddr: u32,
            globalIrqBase: u32,
        },
        src_override: *const extern struct {
            hdr: IrqHeader,
            bus: u8,
            source: u8,
            globalIrq: u32,
            flags: u16,
        },
        lapic_nmi: *const extern struct {
            hdr: IrqHeader align(1),
            uid: u8 align(1),
            flags: u16 align(1),
            lint: u8 align(1),
        },
        unknown: *const extern struct {
            hdr: IrqHeader,
        },

        pub fn from(hdr: *const IrqHeader) IrqCtrlStruct {
            return switch (hdr.kind) {
                0 => .{ .lapic = @ptrCast(@alignCast(hdr)) },
                1 => .{ .io_apic = @ptrCast(@alignCast(hdr)) },
                2 => .{ .src_override = @ptrCast(@alignCast(hdr)) },
                4 => .{ .lapic_nmi = @ptrCast(@alignCast(hdr)) },
                else => .{ .unknown = @ptrCast(@alignCast(hdr)) },
            };
        }
    };
};

comptime {
    const assert = std.debug.assert;
    assert(@sizeOf(Rsdp) == 36);
    assert(@offsetOf(Rsdp, "length") == 20);
    assert(@offsetOf(Rsdp, "extended_checksum") == 32);
    assert(@sizeOf(Header) == 36);
    assert(@offsetOf(Header, "creator_revision") == 32);
}
