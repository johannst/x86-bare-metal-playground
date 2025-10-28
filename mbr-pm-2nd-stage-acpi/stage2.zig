// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

const std = @import("std");
const bios = @import("bios_call.zig");
const acpi = @import("shared/acpi.zig");
const vga = @import("shared/vga.zig");

pub export fn stage2_entry() void {
    var vgabuf = vga.vga(.light_green, .black).init;
    var buf: [32]u8 = undefined;
    var writer = vgabuf.writer(&buf);

    acpiDumpDescriptorTables(&writer.interface) catch |err| {
        writer.print("Failed to dump acpi tables {}", .{err});
    };

    writer.flush();

    while (true) {
        asm volatile ("hlt");
    }
}

// -- ACPI PARSING -------------------------------------------------------------

/// Dump the ACPI System Description Tables.
fn acpiDumpDescriptorTables(w: *std.Io.Writer) !void {
    const rsdp = try acpiFindRsdp();
    switch (rsdp.revision) {
        0 => try acpiWalkRsdt(w, u32, rsdp.rsdt_addr),
        2 => try acpiWalkRsdt(w, u64, rsdp.xsdt_addr),
        else => return error.RsdpUnsupportedRevision,
    }
}

/// Search the RSDP (Root System Description Pointer) in memory for legacy BIOS.
fn acpiFindRsdp() !*const acpi.Rsdp {
    // For legacy BIOS.
    //
    // Find the Root System Description Pointer (RSDP) structure by
    // searching physical memory ranges on 16-byte boundaries for a valid
    // RSDP structure signature and checksum match as follows.
    const regions = [_][2]usize{
        // The first 1 KB of the Extended BIOS Data Area (EBDA).
        .{ 0x8000, 0x8000 + 1024 - 1 },
        // The BIOS read-only memory space between 0E0000h and 0FFFFFh.
        .{ 0xe0000, 0xfffff },
    };

    for (regions) |region| {
        var addr, const end = region;
        while (addr < end) : (addr += 16) {
            const rsdp: *acpi.Rsdp = @ptrFromInt(addr);

            if (!rsdp.validSignature() or !rsdp.validChecksum())
                continue;

            return rsdp;
        }
    }
    return error.RsdpNotFound;
}

/// Go thorugh the RSDT/XSDT (Root/Extended System Description Table) and dump
/// each SDT (System Description Table).
fn acpiWalkRsdt(w: *std.Io.Writer, comptime T: type, paddr: T) !void {
    comptime std.debug.assert(T == u32 or T == u64);

    const rsdt: *const acpi.Header = @ptrFromInt(try toUsizeSafe(paddr));

    const expected_signature: [4]u8 = switch (T) {
        u32 => "RSDT".*,
        u64 => "XSDT".*,
        else => @panic("unimplemented"),
    };

    if (!rsdt.validSignature(expected_signature) or !rsdt.validChecksum())
        return error.RsdtInvalid;

    // The RSDT payload consists of u32 physical addresses to other "System
    // Description Tables". The XSDT payload consists of u64 physical addrs.
    var payload = rsdt.payload() orelse return error.RsdtNoPayload;
    while (@sizeOf(T) <= payload.len) : (payload = payload[@sizeOf(T)..]) {
        // Read physical address of next table.
        const sdt_paddr = std.mem.readVarInt(T, payload[0..@sizeOf(T)], .little);
        // Turn address into pointer to the table header.
        const sdt_hdr: *const acpi.Header = @ptrFromInt(try toUsizeSafe(sdt_paddr));

        switch (sigToInt(&sdt_hdr.signature)) {
            sigToInt("APIC") => try acpiDumpMadt(w, @ptrCast(sdt_hdr)),
            else => try w.print("@0x{x:08} table {s}\n", .{ sdt_paddr, sdt_hdr.signature }),
        }
    }
}

/// Dump the MADT (Multiple APIC Description Table) entries.
fn acpiDumpMadt(w: *std.Io.Writer, madt: *const acpi.Madt) !void {
    std.debug.assert(madt.hdr.validSignature("ACPI".*));

    try w.print("@0x{x:08} table MADT lapic_addr={x} lapic_flags={}\n", .{ @intFromPtr(madt), madt.lapic_paddr, madt.lapic_flags });

    // The MADT payload consists of variable sized interrupt controller structures.
    var payload = madt.payload() orelse return error.MadtNoPayload;
    // While we can at least read the common interrupt header.
    while (payload.len > 1) {
        const hdr: *const acpi.Madt.IrqHeader = @ptrCast(@alignCast(payload[0..]));

        // Do we have enough bytes for the entry.
        if (payload.len < hdr.length)
            return error.MadtInvalidIrqEntry;

        // Re-slice payload to start with next entry.
        defer payload = payload[hdr.length..];

        switch (acpi.Madt.IrqCtrlStruct.from(hdr)) {
            .lapic => |i| try w.print("lapic={}\n", .{i}),
            .io_apic => |i| try w.print("ioapic={}\n", .{i}),
            .src_override => |i| try w.print("src_override={}\n", .{i}),
            .lapic_nmi => |i| try w.print("lapic_nmi={}\n", .{i}),
            inline else => |i| try w.print("{}\n", .{i.hdr}),
        }
    }
}

// -- HELPER -------------------------------------------------------------------

// This example runs in 32-bit protected mode, some addresses in the acpi tables
// may be 64 bit physical addresses. When turning them into pointer we check if
// they fit into an usize.
fn toUsizeSafe(val: u64) !usize {
    if (val > std.math.maxInt(usize))
        return error.LossyTruncate;
    return @truncate(val);
}

fn sigToInt(signature: *const [4]u8) u32 {
    return std.mem.readInt(u32, signature, .little);
}

// -- PANIC HANDLER ------------------------------------------------------------

// Setup our handler as the global panic handler.
pub const panic = std.debug.FullPanic(panicHandler);

// Panic handler which prints the error onto the VGA text buffer.
fn panicHandler(msg: []const u8, first_trace_addr: ?usize) noreturn {
    var vgabuf = vga.vga(11, 0x0).init;
    var buf: [32]u8 = undefined;
    var writer = vgabuf.writer(&buf);

    writer.print("\nPANIC @0x{x:08}: {s}\n", .{ first_trace_addr orelse 0, msg });
    writer.flush();

    while (true) {
        asm volatile ("hlt");
    }
}
