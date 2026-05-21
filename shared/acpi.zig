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

    pub fn validSignature(self: *align(1) const Header, expected: [4]u8) bool {
        return std.mem.eql(u8, &self.signature, &expected);
    }

    pub fn validChecksum(self: *align(1) const Header) bool {
        var sum: u8 = 0;
        for (@as([*]const u8, @ptrCast(self))[0..self.length]) |byte| {
            sum +%= byte;
        }
        return sum == 0;
    }

    pub fn payload(self: *align(1) const Header) ?[]const u8 {
        if (self.length <= @sizeOf(Header))
            return null;
        return @as([*]const u8, @ptrCast(self))[@sizeOf(Header)..self.length];
    }
};

/// Generic Address Struture (GAS).
pub const GenericAddress = extern struct {
    pub const AS_MMIO = 0x00;
    pub const AS_IO = 0x01;

    /// Address space identifier (0=mmio, 1=io, ..).
    address_space_id: u8,
    /// Size in bits of the given register, zero when addressing data structure.
    reg_width: u8,
    /// Bit offset of the register from the address, zero when addressing a data structure.
    reg_offset: u8,
    /// Access size, 1:byte, 2:word, 3:dword, 4:qword, or defined otherwise by address space.
    access_size: u8,
    /// The address of the register or data structure in the given address space.
    /// 0: Physical address of the addressed register or structure.
    /// 1: IO space address of the addressed register or structure.
    addr: u64,
};

/// Fixed ACPI Description Table.
pub const Fadt = extern struct {
    /// Power Management Timer frequency [1].
    /// [1] 4.8.3.3 Power Management Timer (PM_TMR)
    pub const PM_TIMER_HZ = 3579545;

    hdr: Header,
    res: [40]u8,
    /// System port address of the Power Management Timer (unused if x_pm_timer_blk set).
    pm_timer_blk: u32,
    res2: [11]u8,
    /// Register width in bytes for the Power Management Timer (unused if x_pm_timer_blk set).
    pm_timer_len: u8,
    res3: [116]u8,
    /// Extended address of the Power Management Timer (optional).
    x_pm_timer_blk: GenericAddress,
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

    pub fn payload(self: *align(1) const Madt) ?[]const u8 {
        const p = self.hdr.payload() orelse return null;
        // Re-slice additional madt fields.
        return p[@sizeOf(Madt) - @sizeOf(Header) ..];
    }

    /// Common header for each interrupt controller.
    pub const IrqHeader = extern struct {
        kind: u8,
        length: u8,
    };

    /// Interrupt controller structure.
    pub const IrqCtrlStruct = union(enum) {
        lapic: *align(1) const extern struct {
            hdr: IrqHeader,
            uid: u8,
            id: u8,
            flags: u32,
        },
        io_apic: *align(1) const extern struct {
            hdr: IrqHeader,
            id: u8,
            reserved: u8,
            paddr: u32,
            globalIrqBase: u32,
        },
        src_override: *align(1) const extern struct {
            hdr: IrqHeader,
            bus: u8,
            source: u8,
            globalIrq: u32,
            flags: u16,
        },
        lapic_nmi: *align(1) const extern struct {
            hdr: IrqHeader,
            uid: u8,
            flags: u16,
            lint: u8,
        },
        unknown: *align(1) const extern struct {
            hdr: IrqHeader,
        },

        pub fn from(hdr: *const IrqHeader) IrqCtrlStruct {
            return switch (hdr.kind) {
                0 => .{ .lapic = @ptrCast(hdr) },
                1 => .{ .io_apic = @ptrCast(hdr) },
                2 => .{ .src_override = @ptrCast(hdr) },
                4 => .{ .lapic_nmi = @ptrCast(hdr) },
                else => .{ .unknown = @ptrCast(hdr) },
            };
        }
    };
};

/// Memory-Mapped Configuration Space Description Table.
///
/// This is defined in the PCI firmware spec, and not part of the ACPI spec.
/// The PCI spec is behind a paywall, this information was taken from [1].
///
/// With the enhanced configuartion space one can get the physical address to
/// the start of a PCI functions configuration space as follows.
///     base_addr | (bus << 20) | (dev << 15) | (func << 12)
///
/// The physical address per PCI function configuration space spans 4096 bytes
/// (12 bits), which coves the extended (pcie) config space, the first 256 bytes
/// are the compatible (pci) config space [2].
///
/// Seems that there are also some leaked pdfs out there.
/// - PCI Local Bus Specification Revision 3.0
/// - PCI Firmware Specification Revision 3.3
///
/// [1] https://wiki.osdev.org/PCI_Express#Enhanced_Configuration_Mechanism
/// [2] https://wiki.osdev.org/PCI#PCI_Device_Structure
pub const Mcfg = extern struct {
    hdr: Header,
    reserved: u64,

    pub const PciConfigSegment = extern struct {
        base_addr: u64,
        pci_segment: u16,
        bus_start: u8,
        bus_end: u8,
        reserved: u32,
    };

    pub fn payload(self: *align(1) const Mcfg) ?[]align(1) const PciConfigSegment {
        if (self.hdr.length <= @sizeOf(Mcfg))
            return null;
        const n = (self.hdr.length - @sizeOf(Mcfg)) / @sizeOf(PciConfigSegment);
        const b = @as([*]const u8, @ptrCast(self))[@sizeOf(Mcfg)..];
        return @as([*]align(1) const PciConfigSegment, @ptrCast(b))[0..n];
    }
};

comptime {
    const assert = std.debug.assert;

    // PCI values are little endian, only support little endian targets.
    assert(@import("builtin").target.cpu.arch.endian() == .little);

    assert(@sizeOf(Rsdp) == 36);
    assert(@offsetOf(Rsdp, "length") == 20);
    assert(@offsetOf(Rsdp, "extended_checksum") == 32);
    assert(@sizeOf(Header) == 36);
    assert(@offsetOf(Header, "creator_revision") == 32);
    assert(@sizeOf(Mcfg.PciConfigSegment) == 16);
}
