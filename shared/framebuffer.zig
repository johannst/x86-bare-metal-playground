// SPDX-License-Identifier: MIT
//
// Copyright (c) 2026, Johannes Stoelp <dev@memzero.de>

const assert = @import("std").debug.assert;

const Rect = struct { x: usize, y: usize, w: usize, h: usize };

pub fn LinearFramebuffer(T: type) type {
    return struct {
        const Self = @This();

        fb: []T,
        xres: usize,
        yres: usize,
        stride: usize,

        pub fn init(ptr: [*]T, xres: usize, yres: usize, stride_bytes: usize) Self {
            assert(xres * yres <= yres * stride_bytes);

            const stride = stride_bytes / @sizeOf(T);
            return .{
                .fb = ptr[0 .. stride * yres],
                .xres = xres,
                .yres = yres,
                .stride = stride,
            };
        }

        pub fn clear(self: *Self) void {
            @memset(self.fb, 0);
        }

        pub fn clearRect(self: *Self, r: Rect) void {
            if (r.x >= self.xres or r.y >= self.yres)
                return;

            const c0 = r.x;
            const c1 = @min(r.x + r.w, self.xres);
            const r0 = r.y;
            const r1 = @min(r.y + r.h, self.yres);

            for (r0..r1) |row| {
                const row_off = row + self.stride;
                @memset(self.fb[row_off + c0 .. row_off + c1], 0);
            }
        }

        pub fn putPixel(self: *Self, x: usize, y: usize, color: T) void {
            if (x < self.xres and y < self.yres)
                self.fb[y * self.stride + x] = color;
        }

        pub fn subFramebuffer(self: *Self, r: Rect) ?Self {
            if (r.x >= self.xres or r.y >= self.yres)
                return null;

            const c0 = r.x;
            const c1 = @min(r.x + r.w, self.xres);
            const r0 = r.y;
            const r1 = @min(r.y + r.h, self.yres);

            return .{
                .fb = self.fb[r0 * self.stride + c0 .. r1 * self.stride + c1],
                .xres = c1 - c0,
                .yres = r1 - r0,
                .stride = self.stride,
            };
        }
    };
}
