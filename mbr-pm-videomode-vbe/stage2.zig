// SPDX-License-Identifier: MIT
//
// Copyright (c) 2026, Johannes Stoelp <dev@memzero.de>

const std = @import("std");
const com = @import("shared/com.zig");
const vga = @import("shared/vga.zig");
const cpu = @import("shared/cpu.zig");
const vbe = @import("shared/vbe.zig");
const framebuffer = @import("shared/framebuffer.zig");
const swrast = @import("shared/swrast.zig");
const bios = @import("bios_call.zig");

const SegOff = @import("shared/segoff.zig").SegOff;

const Framebuffer = framebuffer.LinearFramebuffer(u32);

pub export fn stage2() void {
    var buf: [128]u8 = undefined;
    var com1 = com.Com.init(com.Com.COM1);
    var iow = com1.writer(&buf);
    //var vga1 = vga.vga(.green, .black).init;
    //var iow = vga1.writer(&buf);

    printVbeModes(&iow.interface) catch {
        iow.print("Failed to print video modes\n", .{});
        iow.flush();
        return;
    };

    const query = ModeQuery{
        .xres = 800,
        .yres = 600,
        .bpp = 32,
        .graphic = true,
        .lfb = true,
    };
    const mode = lookupVbeMode(query) catch {
        iow.print("Failed to lookup video mode {}\n", .{query});
        iow.flush();
        return;
    };
    iow.print("Found requested video mode:\n{s:7} {}\n{s:7} {}\n", .{ "query", query, "resolve", mode });
    iow.flush();

    setupVbeMode(mode) catch {
        iow.print("Failed to setup video mode {}\n", .{query});
        iow.flush();
        return;
    };

    if (!cpu.features().x87) {
        iow.puts("x87 is not supported\n");
        iow.flush();
        return;
    }
    setupX87();

    var fb = Framebuffer.init(
        @as([*]u32, @ptrFromInt(mode.lfb.?)),
        query.xres,
        query.yres,
        mode.stride,
    );

    // Take sub-framebuffer for top-left quadrant.
    var fb_triangle = fb.subFramebuffer(.{ .x = 0, .y = 0, .w = fb.xres / 2, .h = fb.yres / 2 }).?;
    // Take sub-framebuffer for top-right quadrant.
    var fb_chess = fb.subFramebuffer(.{ .x = fb.xres / 2, .y = 0, .w = fb.xres / 2, .h = fb.yres / 2 }).?;
    // Take sub-framebuffer for bottom half.
    var fb_triangle2 = fb.subFramebuffer(.{ .x = 0, .y = fb.yres / 2, .w = fb.xres, .h = fb.yres / 2 }).?;

    drawTriangle(&fb_triangle);

    for (0..10_000) |s| {
        if (s % 8 == 0)
            animateTriangle(&fb_triangle2, s);
        animateChessBoard(&fb_chess, s);
    }
}

// -- SETUP VBE VIDEO MODE -----------------------------------------------------

// INT 0x10 - return VBE controller information, see [1].
//   * in:    ax = 0x4f00
//   * in: es:di = pointer to VbeInfoBlock (signature should be set to 'VBE2').
//   * out:   ax = status code (can pass to checkVbeRet)
//
// INT 0x10 - return VBE mode information, see [2].
//   * in:    ax = 0x4f01
//   * in:    cx = mode
//   * in: es:di = pointer to ModeInfoBlock
//   * out:   ax = status code (can pass to checkVbeRet)
//
// INT 0x10 - set VBE mode, see [3].
//   * in:    ax = 0x4f02
//   * in     bx = video mode (+ request flags)
//                 (1 << 14) use linear framebuffer
//   * out:   ax = status code (can pass to checkVbeRet)
//
// INT 0x10 - get current VBE mode, see [4].
//   * in:    ax = 0x4f03
//   * out:   ax = status code (can pass to checkVbeRet)
//   * out:   bx = current video mode
//
// [1] http://www.ctyme.com/intr/rb-0273.htm
// [2] http://www.ctyme.com/intr/rb-0274.htm
// [3] http://www.ctyme.com/intr/rb-0275.htm
// [4] http://www.ctyme.com/intr/rb-0276.htm

fn printVbeModes(io: *std.Io.Writer) !void {
    var info = vbe.VbeInfoBlock.init();
    // Form an address for 16bit real mode.
    const info16 = try makeSegOff(&info);

    // Get super vga information int=10h ax=4f00h.
    var regs = std.mem.zeroes(bios.RegisterState);
    regs.eax = 0x4f00;
    //regs.es = info16.seg;
    regs.edi = info16.off;
    bios.bios_call(0x10, &regs);
    try vbe.checkVbeRet(@truncate(regs.eax));

    try io.print(
        \\VESA VBE
        \\  signature   {s}
        \\  version     {x}
        \\  vram        {} kB
        \\  oem         {s}
        \\  oem vendor  {s}
        \\  oem product {s}
        \\  oem rev     {s}
        \\
    , .{
        info.signature,
        info.version,
        info.vram_blocks * 64,
        @as([*:0]const u8, @ptrFromInt(info.oem.linear())),
        @as([*:0]const u8, @ptrFromInt(info.oem_vendor_name.linear())),
        @as([*:0]const u8, @ptrFromInt(info.oem_product_name.linear())),
        @as([*:0]const u8, @ptrFromInt(info.oem_product_rev.linear())),
    });
    try io.flush();

    // Iterate over all video modes.
    for (info.modes()) |mode| {
        var minfo = std.mem.zeroes(vbe.ModeInfoBlock);
        // Form an address for 16bit real mode.
        const minfo16 = try makeSegOff(&minfo);

        // Get supver vga mode information, int=10h ax=4f01h.
        regs = std.mem.zeroes(bios.RegisterState);
        regs.eax = 0x4f01;
        regs.ecx = mode;
        //regs.es = minfo16.seg;
        regs.edi = minfo16.off;
        bios.bios_call(0x10, &regs);
        try vbe.checkVbeRet(@truncate(regs.eax));

        try io.print("mode={x:3} {c} res={:4}x{:4} bpp={:2} stride={:5} fb={x:8} supported={}\n", .{
            mode,
            @as(u8, if (minfo.isGraphic()) 'G' else 'T'),
            minfo.x_res,
            minfo.y_res,
            minfo.bits_per_pixel,
            minfo.bytes_per_scan_line,
            if (minfo.hasLinearFramebuffer()) minfo.phys_base else 0xffff_ffff,
            minfo.isSupported(),
        });
        try io.flush();
    }
}

const ModeQuery = struct {
    xres: usize,
    yres: usize,
    bpp: usize = 32,
    graphic: bool = true,
    lfb: bool = true,
};

const ModeResolve = struct {
    mode: u16,
    vram: usize,
    lfb: ?usize,
    stride: usize,
};

fn lookupVbeMode(mq: ModeQuery) !ModeResolve {
    var info = vbe.VbeInfoBlock.init();
    // Form an address for 16bit real mode.
    const info16 = try makeSegOff(&info);

    // Get super vga information int=10h ax=4f00h.
    var regs = std.mem.zeroes(bios.RegisterState);
    regs.eax = 0x4f00;
    //regs.es = info16.seg;
    regs.edi = info16.off;
    bios.bios_call(0x10, &regs);
    try vbe.checkVbeRet(@truncate(regs.eax));

    // Iterate over all video modes.
    for (info.modes()) |mode| {
        var minfo = std.mem.zeroes(vbe.ModeInfoBlock);
        // Form an address for 16bit real mode.
        const minfo16 = try makeSegOff(&minfo);

        // Get supver vga mode information, int=10h ax=4f01h.
        regs = std.mem.zeroes(bios.RegisterState);
        regs.eax = 0x4f01;
        regs.ecx = mode;
        //regs.es = minfo16.seg;
        regs.edi = minfo16.off;
        bios.bios_call(0x10, &regs);
        try vbe.checkVbeRet(@truncate(regs.eax));

        if (!minfo.isSupported())
            continue;
        if (minfo.x_res != mq.xres or minfo.y_res != mq.yres or minfo.bits_per_pixel != mq.bpp)
            continue;
        if (minfo.isGraphic() != mq.graphic or minfo.hasLinearFramebuffer() != mq.lfb)
            continue;

        const lfb = if (mq.graphic) minfo.phys_base else null;

        return .{
            .mode = mode,
            .vram = @as(usize, info.vram_blocks) * 64 * 1024,
            .lfb = lfb,
            .stride = minfo.bytes_per_scan_line,
        };
    }
    return error.VbeRequestedModeNotFound;
}

fn setupVbeMode(mr: ModeResolve) !void {
    const VBE_MODE_USE_LFB: u16 = (1 << 14);

    // Set super vga video mode int=10h ax=4f02h.
    var regs = std.mem.zeroes(bios.RegisterState);
    regs.eax = 0x4f02;
    regs.ebx = mr.mode | if (mr.lfb) |_| VBE_MODE_USE_LFB else 0;
    bios.bios_call(0x10, &regs);
    try vbe.checkVbeRet(@truncate(regs.eax));
}

fn getCurrentVbeMode() !u16 {
    // Set current super vga video mode int=10h ax=4f03h.
    var regs = std.mem.zeroes(bios.RegisterState);
    regs.eax = 0x4f03;
    bios.bios_call(0x10, &regs);
    try vbe.checkVbeRet(@truncate(regs.eax));
}

// -- MAKE SEGOFF --------------------------------------------------------------

fn makeSegOff(ptr: anytype) !SegOff {
    switch (@typeInfo(@TypeOf(ptr))) {
        .pointer => |p| {
            comptime std.debug.assert(p.size == .one);
            const addr = SegOff.from(@intFromPtr(ptr), @sizeOf(p.child)) orelse return error.RealModeAdressOutOfBounds;
            // bios_call currently does not support passing segments.
            return if (addr.seg == 0) addr else error.RealModeSegmentUnsupported;
        },
        else => @compileError("ptr must be a ptr"),
    }
}

// -- SETUP X87 ----------------------------------------------------------------

fn setupX87() void {
    // Setup x87 FPU hardware according to [1].
    //
    // CR0.MP=1  (bit1)
    //   When enabled, trap on fpu operations when CR0.TS=1 (which is set on hardware context switch).
    //   We don't use hardware context switch, however we enable this just as safety measure to trap
    //   if an unexpected hardware context switch occurs.
    // CR0.EM=0  (bit2)
    //   When enabled, trap on fpu operations to emulate them in software.
    // CR0.TS=0  (bit3)
    //   Task switched indicator, set on hardware context switch. In combination with MP=1 this allows
    //   to delay saving the fpu context when it is altered in a new context.
    // CR0.NE=1  (bit5)
    //   When enabled use native exception handling. This triggers an exception (#16) on fpu exceptions
    //   instead of an external interrupt (legacy).
    //
    // [1] Intel vol4 - 10.2 X87 FPU INITIALIZATION
    asm volatile (
        \\mov %%cr0, %%eax
        \\or  $ (1 << 1), %%eax     // CR0.MP=1
        \\and $~(1 << 2), %%eax     // CR0.EM=0
        \\and $~(1 << 3), %%eax     // CR0.TS=0
        \\or  $ (1 << 5), %%eax     // CR0.NE=1
        \\mov %%eax, %%cr0
        \\finit                     // Default initialization of FPU, control word 0x37f.
        \\                          // -> 64bit precision, round nearest, all exceptions masked.
        ::: .{ .eax = true });

    // Setup 53bit precision, 64bit precision makes problems with sin/cos for radians > 2pi.
    asm volatile (
        \\push $0x027f              // 53 bit precision
        \\fldcw (%%esp)
        \\pop %%eax
        ::: .{ .eax = true });
}

fn drawTriangle(fb: *Framebuffer) void {
    swrast.triangle(fb, .{ 0, fb.yres }, .{ fb.xres, fb.yres }, .{ fb.xres / 2, 0 }, 0xff0000, 0x00ff00, 0x0000ff);
}

fn animateTriangle(fb: *Framebuffer, step: usize) void {
    const verts = [3]swrast.Point{
        .{ fb.xres / 4, fb.yres },
        .{ fb.xres / 4 * 3, fb.yres },
        .{ fb.xres / 2, 0 },
    };

    const c1 = @as(u32, 0xff) << @truncate(((step + 0) % 3) * 8);
    const c2 = @as(u32, 0xff) << @truncate(((step + 1) % 3) * 8);
    const c3 = @as(u32, 0xff) << @truncate(((step + 2) % 3) * 8);

    swrast.triangle(fb, verts[0], verts[1], verts[2], c1, c2, c3);
}

fn animateChessBoard(fb: *Framebuffer, step: usize) void {
    const xhalf = fb.xres / 2;
    const yhalf = fb.yres / 2;

    var fb0 = fb.subFramebuffer(.{ .x = 0, .y = 0, .w = xhalf, .h = yhalf }).?; // top-left
    var fb1 = fb.subFramebuffer(.{ .x = xhalf, .y = 0, .w = xhalf, .h = yhalf }).?; // top-right
    var fb2 = fb.subFramebuffer(.{ .x = 0, .y = yhalf, .w = xhalf, .h = yhalf }).?; // bottom-left
    var fb3 = fb.subFramebuffer(.{ .x = xhalf, .y = yhalf, .w = xhalf, .h = yhalf }).?; // bottom-right

    for (0..fb0.yres) |y| {
        for (0..fb0.xres) |x| {
            if (((x + step) / 100 + (y + step) / 100) % 2 == 0) {
                fb0.putPixel(x, y, 0x0000ff);
                fb1.putPixel(x, y, 0x00ff00);
                fb2.putPixel(x, y, 0xff0000);
                fb3.putPixel(x, y, 0xffffff);
            } else {
                fb0.putPixel(x, y, 0);
                fb1.putPixel(x, y, 0);
                fb2.putPixel(x, y, 0);
                fb3.putPixel(x, y, 0);
            }
        }
    }
}
