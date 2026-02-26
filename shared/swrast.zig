// SPDX-License-Identifier: MIT
//
// Copyright (c) 2026, Johannes Stoelp <dev@memzero.de>

const std = @import("std");

pub const Point = [2]usize;
pub const PointSigned = [2]isize;

pub fn toPointSigned(p: Point) PointSigned {
    return .{ @intCast(p[0]), @intCast(p[1]) };
}

// Draw line between point a and point b.
//
// To draw the line we walk along one axis and compute the value
// for the other axis. The strategy is to walk the axis which has
// more pixels as this results in more steps and hence more pixels
// to draw the line.
//
// (a) ###             -
//        ###          dy
//           ### (b)   -
//    |-- dx --|
//
// - For (dx > dy) -> walk the x-axis.
// - For (dx < dy) -> walk the y-axis.
//
// A line between point a and b in 2d space is described by the
// vector equation.
//   line(t) = a + t(b - a)   where t is [0..1]
//
// This can be written as linear equations.
//    x = ax + t(bx - ax)  (i)
//    y = ay + t(by - ay)  (ii)
//
// We can solve (i) for t
//   t = (x - ax) / (bx - ax)
// and substitute t in (ii).
//   y = ay + (by - ay) * (x - ax) / (bx - ax)
// which gives us an equation for y depending on x.
//
// This can be used when walking the x-axis to compute the
// correpsonding pixel for y.
//
// When walking the y-axis we solve the linear equations such that
// we get an equations for x depending on y.
//
// In the concrete implementation we do two things.
// - We transpose the vectors depending on whether we walk the x
//   or y axis.
// - We swap a and b such that we always walk from left to right.
//
// [1] https://en.wikipedia.org/wiki/Line_(geometry)#Vectors
pub fn line(fb: anytype, a: Point, b: Point, color: u32) void {
    var ax, var ay = toPointSigned(a);
    var bx, var by = toPointSigned(b);
    const steep = @abs(bx - ax) < @abs(by - ay);

    if (steep) {
        std.mem.swap(isize, &ax, &ay);
        std.mem.swap(isize, &bx, &by);
    }
    if (ax > bx) {
        std.mem.swap(isize, &ax, &bx);
        std.mem.swap(isize, &ay, &by);
    }

    var x = ax;
    while (x < bx) : (x += 1) {
        // Optimization: Stop if the line goes out of the fb resolution.
        if (x >= if (steep) fb.yres else fb.xres)
            break;

        const y = ay + @divTrunc((by - ay) * (x - ax), (bx - ax));

        var xi = @as(usize, @intCast(x));
        var yi = @as(usize, @intCast(y));

        if (steep) {
            std.mem.swap(usize, &xi, &yi);
        }

        fb.putPixel(xi, yi, color);
    }
}

// Draw triangle spanned between points a, b and c.
//
// Points *must* be ordered counter clock-wise (CCW).
//
// The computation whether a point is inside or outside the triangle is based
// on using the line function as signed half-space function. This means, the
// line function between two points is used to separate two half planes, which are
// distinguished by the sign of the function evaluated for a given point p.
//
// A line between point a and b in 2d space is described by the
// vector equation.
//   line(t) = a + t(b - a)   where t is [0..1]
//
// This can be written as linear equations.
//    x = ax + t(bx - ax)  (i)
//    y = ay + t(by - ay)  (ii)
//
// We can solve (i) for t.
//   t = (x - ax) / (bx - ax)
// Substitute t in (ii)
//   y = ay + (by - ay) * (x - ax) / (bx - ax)
// and shift the terms a bit.
//   0 = (bx - ax) * (ay - y) + (by - ay) * (x - ax)
// Which gives the signed half-space function for the line (see,
// signedHalfSpaceLine).
//
// For a point p this function evaluates to a positive number if the point is
// "left" of the line and a negative number if the point is "right" of the line.
// Where left and right are relative to the direction the line points.
//
// In the implementation below the signedHalfSpaceLine function is evaluated for
// a point P for each line (which makes a side of the triangle). If all results
// evaluate to a postive number the point is inside the triangle.
// Due to this implementation choice, point a, b and c must be orirented CCW.
//
// [1] https://web.archive.org/web/20050408192410/http://sw-shader.sourceforge.net/rasterizer.html
// [2] https://jtsorlinis.github.io/rendering-tutorial/
pub fn triangle(fb: anytype, a: Point, b: Point, c: Point, c1: u32, c2: u32, c3: u32) void {
    // Bounding rectangle.
    const xmin = @min(a[0], b[0], c[0]);
    const xmax = @max(a[0], b[0], c[0]);
    const ymin = @min(a[1], b[1], c[1]);
    const ymax = @max(a[1], b[1], c[1]);

    const rgb = struct {
        fn from(v: u32) [3]u8 {
            return .{ @truncate(v), @truncate(v >> 8), @truncate(v >> 16) };
        }
        fn to(v: [3]u8) u32 {
            return (@as(u32, v[0]) & 0xff) << 16 | (@as(u32, v[1]) & 0xff) << 8 | (@as(u32, v[2]) & 0xff);
        }
    };

    const abc = signedHalfSpaceLine(a, b, c);

    for (ymin..ymax) |y| {
        for (xmin..xmax) |x| {
            const p = Point{ x, y };
            const abp = signedHalfSpaceLine(a, b, p);
            const bcp = signedHalfSpaceLine(b, c, p);
            const cap = signedHalfSpaceLine(c, a, p);

            if (abp > 0 and bcp > 0 and cap > 0) {
                const col = if (c1 == c2 and c1 == c3) c1 else brk: {
                    const b1, const g1, const r1 = rgb.from(c1);
                    const b2, const g2, const r2 = rgb.from(c2);
                    const b3, const g3, const r3 = rgb.from(c3);

                    const cr = @abs(@divTrunc(r1 * abp + r2 * bcp + r3 * cap, abc));
                    const cg = @abs(@divTrunc(g1 * abp + g2 * bcp + g3 * cap, abc));
                    const cb = @abs(@divTrunc(b1 * abp + b2 * bcp + b3 * cap, abc));
                    break :brk rgb.to(.{ @truncate(cb), @truncate(cg), @truncate(cr) });
                };

                fb.putPixel(x, y, @truncate(col));
            }
        }
    }
}

fn signedHalfSpaceLine(a: Point, b: Point, p: Point) isize {
    const ax, const ay = toPointSigned(a);
    const bx, const by = toPointSigned(b);
    const px, const py = toPointSigned(p);
    return (ay - py) * (bx - ax) + (px - ax) * (by - ay);
}
