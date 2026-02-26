// SPDX-License-Identifier: MIT
//
// Copyright (c) 2026, Johannes Stoelp <dev@memzero.de>

const std = @import("std");
const com = @import("shared/com.zig");
const cpu = @import("shared/cpu.zig");
const swr = @import("shared/swrast.zig");
const bios = @import("bios_call.zig");

const line = swr.line;
const Point = swr.Point;

// Set video mode 13h, see [1] & [2].
//   * 320x200 graphic mode
//   * 256 colors (8bit per pixel)
//   * 0xA0000 screen address
//   * linear addressing [3]
//
// Set video mode 12h, see [1].
//   * 640x480 graphic mode
//   * 16 colors (4bit per pixel)
//   * 0xA0000 screen address
//   * planar addressing (4 planes) [3]
//
// Set video mode 6ah, see [1].
//   * 800x600 graphic mode
//   * 16 colors (4bit per pixel)
//   * 0xA0000 screen address
//   * planar addressing (4 planes) [3]
//
// [1] http://www.ctyme.com/intr/rb-0069.htm
// [2] https://en.wikipedia.org/wiki/Mode_13h (shows color palette)
// [3] http://www.techhelpmanual.com/89-video_memory_layouts.html
// [4] https://github.com/qemu/seabios/blob/106549a4362f6b499da522f8f8f5ed9f98388f87/vgasrc/stdvgamodes.c#L283
//
const VIDEO_MODE = 0x13;
//const VIDEO_MODE = 0x12;
//const VIDEO_MODE = 0x6a;

pub export fn stage2() void {
    var buf: [128]u8 = undefined;
    var com1 = com.Com.init(com.Com.COM1);
    var iow = com1.writer(&buf);

    if (!setupVideoMode(VIDEO_MODE)) {
        iow.print("Failed to change video mode\n", .{});
        iow.flush();
        return;
    }

    if (!cpu.features().x87) {
        iow.puts("x87 is not supported\n");
        iow.flush();
        return;
    }
    setupX87();

    var fb = Framebuffer{};
    drawSinCos(&fb);

    for (0..10_000) |step| {
        animateRectangle(&fb, step);
        animateCube(&fb, step);
        burnCycles(500_000_000);
    }
}

// -- SETUP VIDEO MODE ---------------------------------------------------------

fn setupVideoMode(mode: u8) bool {
    // Set video mode int=10h, ah=00h, see [1].
    // [1] http://www.ctyme.com/intr/int-10.htm
    var regs = std.mem.zeroes(bios.RegisterState);
    regs.eax = mode;
    bios.bios_call(0x10, &regs);

    return !regs.cf();
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

fn burnCycles(cycles: u64) void {
    const rdtsc = struct {
        fn call() u64 {
            var eax: u32, var edx: u32 = .{ undefined, undefined };
            asm volatile ("rdtsc"
                : [eax] "={eax}" (eax),
                  [edx] "={edx}" (edx),
            );
            return (@as(u64, edx) << 32) | eax;
        }
    }.call;

    const start = rdtsc();
    while ((rdtsc() - start) < cycles) {
        asm volatile ("pause" ::: .{ .memory = true });
    }
}

// -- FRAMEBUFFER --------------------------------------------------------------

const Vec2 = [2]f64;
const Vec3 = [3]f64;

const Rect = struct { x: usize, y: usize, w: usize, h: usize };

const Framebuffer = switch (VIDEO_MODE) {
    0x13 => GenericFramebuffer(.linear, 320, 200),
    0x12 => GenericFramebuffer(.planar, 640, 480),
    0x6a => GenericFramebuffer(.planar, 800, 600),
    else => @compileError(std.fmt.comptimePrint("Unsupported video mode {x}", .{VIDEO_MODE})),
};

const FbMemLayout = enum {
    linear,
    planar,
};

// Create a framebuffer type which treats the VGA graphic segment starting at
// 0xA000:0000 either with linear or planar memory layout. For the planar memory
// layout this implementation only supports one plane, and hence one can only
// use it as monochrome framebuffer.
fn GenericFramebuffer(comptime layout: FbMemLayout, cols: comptime_int, rows: comptime_int) type {
    return struct {
        const Self = @This();
        const COLS = cols;
        const ROWS = rows;

        // Take a slice to VGA video memory (graphic mode).
        fb: []u8 = @as([*]u8, @ptrFromInt(0xA0000))[0 .. Self.COLS * Self.ROWS],
        // Satisfy swrast.line interface.
        xres: usize = cols,
        yres: usize = rows,

        fn clear(self: *Self) void {
            const black = 0;
            @memset(self.fb, black);
        }

        fn clearRect(self: *Self, r: Rect) void {
            const c0 = r.x;
            const c1 = @min(r.x + r.w, Self.COLS);
            const r0 = r.y;
            const r1 = @min(r.y + r.h, Self.ROWS);

            for (r0..r1) |row| {
                const black = 0;
                switch (comptime layout) {
                    .linear => @memset(self.fb[row * Self.COLS + c0 .. row * Self.COLS + c1], black),
                    .planar => @memset(self.fb[row * Self.COLS / 8 + c0 / 8 .. row * Self.COLS / 8 + c1 / 8], black),
                }
            }
        }

        pub fn putPixel(self: *Self, x: usize, y: usize, color: u8) void {
            switch (comptime layout) {
                .linear => self.fb[y * Self.COLS + x] = color,
                .planar => self.fb[y * Self.COLS / 8 + x / 8] |= @as(u8, 1) << (7 - @as(u3, @truncate(x))),
            }
        }
    };
}

// -- DRAW SIN COS -------------------------------------------------------------

fn drawSinCos(fb: *Framebuffer) void {
    const num_period = 4;
    const x_axis = Framebuffer.ROWS / 8;
    const y_project = struct {
        fn call(x: f64) usize {
            // y-axis points downwards, project as it points upwards.
            const y_altitude = -Framebuffer.ROWS / 10;
            return @intCast(x_axis + @as(isize, @intFromFloat(y_altitude * x)));
        }
    }.call;

    // Draw the x axis.
    line(fb, .{ 0, x_axis }, .{ Framebuffer.COLS - 1, x_axis }, 10);

    for (0..Framebuffer.COLS) |x| {
        const rad = @divExact(2.0 * std.math.pi * num_period * @as(f64, @floatFromInt(x)), Framebuffer.COLS);
        // Draw sin.
        fb.putPixel(x, y_project(@sin(rad)), 42);
        // Draw cos.
        fb.putPixel(x, y_project(@cos(rad)), 84);
    }
}

// -- ANIMATE RECTANGLE --------------------------------------------------------

fn animateRectangle(fb: *Framebuffer, s: usize) void {
    // Transform from normalized device coordinate (NDC) where (0,0) is the center and x,y range from [-1, 1],
    // to screen coordinates where (0,0) is in the top left corner and and x-axis goes right, and y-axis down.
    //
    //  (-1,1)   (1,1)      (0,0)   (W,0)
    //     +-------+          +-------+
    // NDC | (0,0) | -------> |       | screen
    //     +-------+          +-------+
    //  (-1,-1)  (1,-1)     (0,H)   (W,H)
    const toScreenCoord = struct {
        fn call(a: Vec2) Point {
            return .{
                // Move x-axis to the left [0, 2] and then scale by half the screen width.
                @intFromFloat((a[0] + 1) * @as(f32, @floatFromInt(Framebuffer.COLS - 1)) / 2),
                // Mirror y-axis & move up [0, 2] and then scale by half the screen height.
                @intFromFloat((-a[1] + 1) * @as(f32, @floatFromInt(Framebuffer.ROWS - 1)) / 2),
            };
        }
    }.call;

    // Rotate NDC point for given radians RAD (multiply rotation matrix).
    const rotate = struct {
        fn call(a: Vec2, rad: f64) Vec2 {
            return .{
                a[0] * @cos(rad) - a[1] * @sin(rad),
                a[0] * @sin(rad) + a[1] * @cos(rad),
            };
        }
    }.call;

    // Translate NDC point by given translation TRANS.
    const translate = struct {
        fn call(a: Vec2, trans: Vec2) Vec2 {
            return .{
                a[0] + trans[0],
                a[1] + trans[1],
            };
        }
    }.call;

    // Vertices of a 2d rectangle.
    const vertices = [_]Vec2{
        .{ -0.2, 0.2 },
        .{ 0.2, 0.2 },
        .{ 0.2, -0.2 },
        .{ -0.2, -0.2 },
    };

    // Transformation pipeline.
    const transform = struct {
        fn call(a: Vec2, step: usize) Vec2 {
            const rad = @as(f64, @floatFromInt(step)) * 0.1 * std.math.pi;
            const trans_animate = if ((step % 40) < 20) .{ 0.25 * @sin(rad), 0 } else .{ 0, 0.25 * @sin(rad) };
            const trans_move = .{ -0.5, -0.5 };
            return translate(translate(rotate(a, rad), trans_animate), trans_move);
        }
    }.call;

    const col = 42 + @as(u8, @truncate(s));

    // Transform and draw rectangle to screen.
    for (0..4) |i| {
        line(fb, toScreenCoord(transform(vertices[i % 4], s)), toScreenCoord(transform(vertices[(i + 1) % 4], s)), col);
    }
}

// -- ANIMATE CUBE -------------------------------------------------------------

fn animateCube(fb: *Framebuffer, s: usize) void {
    // Transform from normalized device coordinate (NDC) where (0,0) is the center and x,y range from [-1, 1],
    // to screen coordinates where (0,0) is in the top left corner and and x-axis goes right, and y-axis down.
    //
    //  (-1,1)   (1,1)      (0,0)   (W,0)
    //     +-------+          +-------+
    // NDC | (0,0) | -------> |       | screen
    //     +-------+          +-------+
    //  (-1,-1)  (1,-1)     (0,H)   (W,H)
    const toScreenCoord = struct {
        fn call(a: Vec3) Point {
            // Project point from 3d space to 2d space using weak perspective projection [1].
            // Assume the camera is at (0,0,1), and 3d points are projected onto
            // the 2d space spanning [-1,1] in the xy plane.
            //
            // [1] https://en.wikipedia.org/wiki/3D_projection#Weak_perspective_projection
            const x: f64 = a[0] / (1 + a[2]);
            const y: f64 = a[1] / (1 + a[2]);

            // To screen coordinates.
            return .{
                // Move x-axis to the left [0, 2] and then scale by half the screen width.
                @intFromFloat((x + 1) * @as(f32, @floatFromInt(Framebuffer.COLS - 1)) / 2),
                // Mirror y-axis & move up [0, 2] and then scale by half the screen height.
                @intFromFloat((-y + 1) * @as(f32, @floatFromInt(Framebuffer.ROWS - 1)) / 2),
            };
        }
    }.call;

    // Rotate NDC point for given radians RAD in xz plane (multiply rotation matrix).
    const rotateXZ = struct {
        fn call(a: Vec3, rad: f64) Vec3 {
            return .{
                a[0] * @cos(rad) - a[2] * @sin(rad),
                a[1],
                a[0] * @sin(rad) + a[2] * @cos(rad),
            };
        }
    }.call;

    // Translate NDC point by given translation TRANS.
    const translate = struct {
        fn call(a: Vec3, trans: Vec3) Vec3 {
            return .{
                a[0] + trans[0],
                a[1] + trans[1],
                a[2] + trans[2],
            };
        }
    }.call;

    // Vertices of a 3d cube.
    const vertices = [_]Vec3{
        // Front face.
        .{ 0.25, 0.25, 0.25 },
        .{ -0.25, 0.25, 0.25 },
        .{ -0.25, -0.25, 0.25 },
        .{ 0.25, -0.25, 0.25 },
        // Back face.
        .{ 0.25, 0.25, -0.25 },
        .{ -0.25, 0.25, -0.25 },
        .{ -0.25, -0.25, -0.25 },
        .{ 0.25, -0.25, -0.25 },
    };

    // Transformation pipeline.
    const transform = struct {
        fn call(a: Vec3, step: usize) Vec3 {
            const rad = @as(f64, @floatFromInt(step)) * 0.1 * std.math.pi;
            const trans_xy = .{ 0.4, -0.4, 0 };
            return translate(rotateXZ(a, rad), trans_xy);
        }
    }.call;

    fb.clearRect(.{ .x = Framebuffer.COLS / 2, .y = Framebuffer.ROWS / 2, .w = Framebuffer.COLS / 2, .h = Framebuffer.ROWS / 2 });

    for (0..4) |i| {
        const col = 10;

        // Front face.
        const a0 = vertices[(i + 0) % 4];
        const a1 = vertices[(i + 1) % 4];
        line(fb, toScreenCoord(transform(a0, s)), toScreenCoord(transform(a1, s)), col);

        // Back face.
        const b0 = vertices[4 + (i + 0) % 4];
        const b1 = vertices[4 + (i + 1) % 4];
        line(fb, toScreenCoord(transform(b0, s)), toScreenCoord(transform(b1, s)), col);

        // Side faces.
        const c0 = vertices[i];
        const c1 = vertices[i + 4];
        line(fb, toScreenCoord(transform(c0, s)), toScreenCoord(transform(c1, s)), col);
    }
}
