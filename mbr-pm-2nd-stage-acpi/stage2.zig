// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

const std = @import("std");
const bios = @import("bios_call.zig");
const acpi = @import("shared/acpi.zig");
const pci = @import("shared/pci.zig");

var iob: [64]u8 = undefined;
var iow: ?*std.Io.Writer = null;

pub export fn stage2_entry() void {
    //const vga = @import("shared/vga.zig");
    //var vgactx = vga.vga(.light_green, .black).init;
    //var writer = vgactx.writer(&iob);
    const com = @import("shared/com.zig");
    var comctx = com.Com.init(com.Com.COM1);
    var writer = comctx.writer(&iob);
    iow = &writer.interface;

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

    const rsdt: *align(1) const acpi.Header = @ptrFromInt(try toUsizeSafe(paddr));

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
        const sdt_paddr = std.mem.readInt(T, payload[0..@sizeOf(T)], .little);
        // Turn address into pointer to the table header.
        const sdt_hdr: *align(1) const acpi.Header = @ptrFromInt(try toUsizeSafe(sdt_paddr));

        switch (sigToInt(&sdt_hdr.signature)) {
            sigToInt("FACP") => try acpiDumpFadt(w, @ptrCast(sdt_hdr)),
            sigToInt("APIC") => try acpiDumpMadt(w, @ptrCast(sdt_hdr)),
            sigToInt("MCFG") => try acpiDumpMcfg(w, @ptrCast(sdt_hdr)),
            else => try w.print("@0x{x:08} table {s}\n", .{ sdt_paddr, sdt_hdr.signature }),
        }
    }
}

/// Dump the FADT (Fixed ACPI Description Table).
fn acpiDumpFadt(w: *std.Io.Writer, fadt: *align(1) const acpi.Fadt) !void {
    std.debug.assert(fadt.hdr.validSignature("FACP".*));

    try w.print("@0x{x:08} table FACP\n", .{@intFromPtr(fadt)});

    if (fadt.x_pm_timer_blk.address_space_id != acpi.GenericAddress.AS_IO) {
        return error.PowerManagementTimerNotInIoSpace;
    }
    if (fadt.x_pm_timer_blk.reg_width != 32) {
        return error.PowerManagementTimerUnhandledRegsiterSize;
    }

    // IO address space is 16bit.
    std.debug.assert(fadt.x_pm_timer_blk.addr <= std.math.maxInt(u16));
    const pm_port: u16 = @truncate(fadt.x_pm_timer_blk.addr);
    try w.print("PM timer at io port 0x{x}\n", .{pm_port});

    // Read the power management timer value.
    try w.print("PM timer value {}\n", .{inl(pm_port)});
    try w.print("PM timer value {}\n", .{inl(pm_port)});
    try w.print("PM timer value {}\n", .{inl(pm_port)});
    try w.print("PM timer value {}\n", .{inl(pm_port)});

    // Spin for 2 seconds.
    try w.writeAll("start counting for 2s .. ");
    try w.flush();
    const start = inl(pm_port);
    while (inl(pm_port) -% start < (2 * acpi.Fadt.PM_TIMER_HZ)) {
        asm volatile ("pause");
    }
    try w.writeAll("done\n");
    try w.flush();
}

/// Dump the MADT (Multiple APIC Description Table) entries.
fn acpiDumpMadt(w: *std.Io.Writer, madt: *align(1) const acpi.Madt) !void {
    std.debug.assert(madt.hdr.validSignature("APIC".*));

    try w.print("@0x{x:08} table MADT lapic_addr={x} lapic_flags={}\n", .{ @intFromPtr(madt), madt.lapic_paddr, madt.lapic_flags });

    // The MADT payload consists of variable sized interrupt controller structures.
    var payload = madt.payload() orelse return error.MadtNoPayload;
    // While we can at least read the common interrupt header.
    while (payload.len > 1) {
        const hdr: *align(1) const acpi.Madt.IrqHeader = @ptrCast(payload[0..]);

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

/// Dump the MCFG (Memory-mapped Configuration Space Description Table) entries.
fn acpiDumpMcfg(w: *std.Io.Writer, mcfg: *align(1) const acpi.Mcfg) !void {
    std.debug.assert(mcfg.hdr.validSignature("MCFG".*));

    // Go through all pci busses and devices print available functions.
    const configs = mcfg.payload() orelse return error.McfgNoPayload;
    for (configs) |conf| {
        for (conf.bus_start..conf.bus_end) |bus| {
            for (0..32) |dev| {
                try dumpPciFunctionConfigSpace(w, conf.base_addr, @intCast(bus), @intCast(dev), 0);
            }
        }
    }
}

///
fn dumpPciFunctionConfigSpace(w: *std.Io.Writer, base_addr: u64, bus: u8, dev: u5, func: u3) !void {
    // The base address is relative to the bus 0. Each config space spans 4096 bytes (12 bits).
    const paddr = base_addr | (@as(u64, bus) << 20) | (@as(u64, dev) << 15) | (@as(u64, func) << 12);
    std.debug.assert(paddr % @alignOf(pci.ConfigSpaceHeader) == 0);
    const funcp = @as(*pci.ConfigSpaceHeader, @ptrFromInt(try toUsizeSafe(paddr)));

    // Skip, invalid vendor id.
    if (funcp.vendor_id == 0xffff)
        return;

    // Skip, only handle general PCI functions (eg no 01h pci-to-pci bridge, 02h cardbus bridge).
    if (funcp.header.type != 0)
        return;

    try w.print("{x:02}:{x:02}.{x:02} v:d={x:04}:{x:04} sv:sd={x:04}:{x:04} class={x} subclass={x} caps={}\n", .{
        bus,
        dev,
        func,
        funcp.vendor_id,
        funcp.device_id,
        funcp.subvendor_id,
        funcp.subdevice_id,
        funcp.class,
        funcp.subclass,
        (funcp.status >> 4) & 1,
    });

    // Dump any IO or MMIO base address register (bar).
    var idx: usize = 0;
    while (idx < funcp.bar.len) : (idx += 1) {
        // Skip, unused bar.
        if (funcp.bar[idx] == 0)
            continue;

        const prefix, const base, const size = brk: {
            if (pci.Bar.is64(funcp.bar[idx])) {
                std.debug.assert(idx < funcp.bar.len - 1);
                // Consume next bar, as this was a 64 bit bar.
                defer idx += 1;

                var bar = pci.Bar64{ .regl = &funcp.bar[idx], .regh = &funcp.bar[idx + 1] };
                break :brk .{ "mmio64", bar.base(), bar.size() };
            } else {
                var bar = pci.Bar{ .reg = &funcp.bar[idx] };
                break :brk .{ if (bar.io()) "i/o" else "mmio32", bar.base(), bar.size() };
            }
        };
        try w.print("{s:8} {x}-{x} [{x}]\n", .{ prefix, base, base + size, size });
    }

    // If multi-function device, dump other functions as well.
    if (func == 0 and funcp.header.multi_function) {
        for (1..7) |subfunc| {
            try dumpPciFunctionConfigSpace(w, base_addr, bus, dev, @truncate(subfunc));
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

inline fn inl(port: u16) u32 {
    var val: u32 = 0;
    _ = asm volatile ("inl %[dx], %[eax]"
        : [eax] "={eax}" (val),
        : [dx] "{dx}" (port),
    );
    return val;
}

// -- PANIC HANDLER ------------------------------------------------------------

// Setup our handler as the global panic handler.
pub const panic = std.debug.FullPanic(panicHandler);

// Panic handler which prints the error onto the VGA text buffer.
fn panicHandler(msg: []const u8, first_trace_addr: ?usize) noreturn {
    if (iow) |w| {
        w.print("\nPANIC @0x{x:08}: {s}\n", .{ first_trace_addr orelse 0, msg }) catch {};
        w.flush() catch {};
    }

    while (true) {
        asm volatile ("hlt");
    }
}
