// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

const std = @import("std");

/// An inclusive range.
/// Using C abi as this will be shared between 32 and 64 bit code at runtime.
pub const Range = extern struct {
    start: u64,
    end: u64,

    fn overlaps(self: Range, other: Range) bool {
        return self.start <= other.end and self.end >= other.start;
    }

    fn touches(self: Range, other: Range) bool {
        return self.start == other.end +| 1 or self.end +| 1 == other.start;
    }

    fn contains(self: Range, other: Range) bool {
        return self.start <= other.start and self.end >= other.end;
    }

    fn encloses(self: Range, other: Range) bool {
        return self.start < other.start and self.end > other.end;
    }
};

/// A set of non-overlapping ranges with at most N ranges.
/// Using C abi as this will be shared between 32 and 64 bit code at runtime.
pub fn RangeSet(comptime N: u8) type {
    return extern struct {
        ranges: [N]Range,
        used: u8,

        pub const init: @This() = std.mem.zeroes(@This());

        fn push(self: *@This(), r: Range) !void {
            if (self.used == N)
                return error.OutOfRanges;
            self.ranges[self.used] = r;
            self.used += 1;
        }

        fn pop(self: *@This(), idx: usize) !void {
            std.debug.assert(idx < self.used);
            // If idx points into the middle of the ranges, move following
            // ranges after idx one slot forward.
            if (idx < self.used - 1)
                @memmove(self.ranges[idx .. self.used - 1], self.ranges[idx + 1 .. self.used]);
            self.used -= 1;
        }

        pub fn insert(self: *@This(), in_range: Range) !void {
            var new_range = in_range;
            // Merge all ranges that touch or overlap with in_range.
            restart: while (true) {
                for (self.ranges[0..self.used], 0..) |range, idx| {
                    if (!new_range.overlaps(range) and !new_range.touches(range))
                        continue;
                    new_range.start = @min(range.start, new_range.start);
                    new_range.end = @max(range.end, new_range.end);
                    try self.pop(idx);
                    continue :restart;
                }
                break;
            }
            try self.push(new_range);
        }

        pub fn remove(self: *@This(), rm_range: Range) !void {
            restart: while (true) {
                // Remove or adjust all ranges that overlap with rm_range.
                for (self.ranges[0..self.used], 0..) |*range, idx| {
                    if (!range.overlaps(rm_range))
                        continue;
                    // The range and rm_range overlap, distinguish the following.
                    // (a) The range is fully contained in the to be removed range.
                    //       rm |----------|
                    //       r    |----|
                    //  -> Remove range r.
                    // (b) The range overlaps on the left side with the to be removed range.
                    //       rm |----|
                    //       r    |----|
                    //  -> Adjust start of range r.
                    // (c) The range overlaps on the right side with the to be removed range.
                    //       rm      |---|
                    //       r    |----|
                    //  -> Adjust end of range r.
                    // (d) The to be removed range is enclosed by the range.
                    //       rm    |----|
                    //       r  |----------|
                    //  -> Split range r into two (create hole).
                    if (rm_range.contains(range.*)) {
                        try self.pop(idx);
                        continue :restart;
                    } else if (rm_range.start <= range.start) {
                        range.start = rm_range.end +| 1;
                    } else if (rm_range.end >= range.end) {
                        range.end = rm_range.start -| 1;
                    } else {
                        std.debug.assert(range.encloses(rm_range));
                        range.end = rm_range.start -| 1;
                        return try self.push(.{ .start = rm_range.end +| 1, .end = range.end });
                    }
                }
                break :restart;
            }
        }

        pub fn alloc(self: *@This(), size: u64, comptime alignment: u64) ?u64 {
            if (size == 0 or !std.math.isPowerOfTwo(alignment))
                return null;

            for (self.ranges[0..self.used]) |range| {
                // Consume front padding until start is properly aligned.
                const start = std.mem.alignForward(u64, range.start, alignment);
                const end = (std.math.add(u64, start, size) catch return null) - 1;

                // Check if range can handle the allocation.
                if (end > range.end)
                    continue;

                // Remove range (including front padding). Range valid, ignore error.
                self.remove(.{ .start = range.start, .end = end }) catch unreachable;
                return start;
            }
            return null;
        }

        pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
            for (self.ranges[0..self.used]) |r| {
                try writer.print("{x:08}-{x:08}\n", .{ r.start, r.end });
            }
        }
    };
}

test "Range" {
    const expect = std.testing.expect;
    const testee = Range{ .start = 0x10, .end = 0x20 };

    try expect(testee.overlaps(.{ .start = 0x10, .end = 0x10 }));
    try expect(testee.overlaps(.{ .start = 0x20, .end = 0x20 }));
    try expect(testee.overlaps(.{ .start = 0x0, .end = 0x18 }));
    try expect(testee.overlaps(.{ .start = 0x18, .end = 0x30 }));
    try expect(testee.overlaps(.{ .start = 0x0, .end = 0x30 }));

    try expect(testee.touches(.{ .start = 0x0, .end = 0xf }));
    try expect(testee.touches(.{ .start = 0x21, .end = 0x30 }));

    try expect(testee.contains(.{ .start = 0x11, .end = 0x11 }));
    try expect(testee.contains(.{ .start = 0x1f, .end = 0x1f }));
    try expect(testee.contains(.{ .start = 0x11, .end = 0x1f }));
    try expect(testee.contains(.{ .start = 0x10, .end = 0x10 }));
    try expect(testee.contains(.{ .start = 0x20, .end = 0x20 }));
    try expect(testee.contains(.{ .start = 0x10, .end = 0x20 }));
    try expect(!testee.contains(.{ .start = 0x0, .end = 0xf }));
    try expect(!testee.contains(.{ .start = 0x21, .end = 0x30 }));
    try expect(!testee.contains(.{ .start = 0x0, .end = 0x30 }));

    try expect(testee.encloses(.{ .start = 0x11, .end = 0x11 }));
    try expect(testee.encloses(.{ .start = 0x1f, .end = 0x1f }));
    try expect(testee.encloses(.{ .start = 0x11, .end = 0x1f }));
    try expect(!testee.encloses(.{ .start = 0x10, .end = 0x10 }));
    try expect(!testee.encloses(.{ .start = 0x20, .end = 0x20 }));
    try expect(!testee.encloses(.{ .start = 0x10, .end = 0x20 }));
    try expect(!testee.encloses(.{ .start = 0x0, .end = 0xf }));
    try expect(!testee.encloses(.{ .start = 0x21, .end = 0x30 }));
    try expect(!testee.encloses(.{ .start = 0x0, .end = 0x30 }));
}

test "RangeSet" {
    const expect = std.testing.expect;
    const expectError = std.testing.expectError;
    const expectEqual = std.testing.expectEqual;
    var testee = RangeSet(4).init;

    try testee.insert(.{ .start = 0x10, .end = 0x20 });
    try testee.insert(.{ .start = 0x10, .end = 0x20 });
    try expect(testee.used == 1);
    try expectEqual(Range{ .start = 0x10, .end = 0x20 }, testee.ranges[0]);
    // Insert touch left.
    try testee.insert(.{ .start = 0x8, .end = 0xf });
    try expect(testee.used == 1);
    try expectEqual(Range{ .start = 0x8, .end = 0x20 }, testee.ranges[0]);
    // Insert touch right.
    try testee.insert(.{ .start = 0x21, .end = 0x28 });
    try expect(testee.used == 1);
    try expectEqual(Range{ .start = 0x8, .end = 0x28 }, testee.ranges[0]);
    // Insert overlap left.
    try testee.insert(.{ .start = 0x1, .end = 0x10 });
    try expect(testee.used == 1);
    try expectEqual(Range{ .start = 0x1, .end = 0x28 }, testee.ranges[0]);
    // Insert overlap right.
    try testee.insert(.{ .start = 0x20, .end = 0x2f });
    try expect(testee.used == 1);
    try expectEqual(Range{ .start = 0x1, .end = 0x2f }, testee.ranges[0]);
    // Insert overlap full.
    try testee.insert(.{ .start = 0, .end = 0x100 });
    try expect(testee.used == 1);
    try expectEqual(Range{ .start = 0x0, .end = 0x100 }, testee.ranges[0]);
    // Insert containing.
    try testee.insert(.{ .start = 0x10, .end = 0x20 });
    try expect(testee.used == 1);
    try expectEqual(Range{ .start = 0x0, .end = 0x100 }, testee.ranges[0]);
    // Insert non-overlap, non-touch.
    try testee.insert(.{ .start = 0x200, .end = 0x300 });
    try testee.insert(.{ .start = 0x400, .end = 0x500 });
    try testee.insert(.{ .start = 0x600, .end = 0x700 });
    try expect(testee.used == 4);
    try expectEqual(Range{ .start = 0x0, .end = 0x100 }, testee.ranges[0]);

    try expectError(error.OutOfRanges, testee.insert(.{ .start = 0x800, .end = 0x900 }));

    // Subtract left.
    try testee.remove(.{ .start = 0x0, .end = 0x0 });
    try expect(testee.used == 4);
    try expectEqual(Range{ .start = 0x1, .end = 0x100 }, testee.ranges[0]);
    try testee.remove(.{ .start = 0x0, .end = 0xf });
    try expect(testee.used == 4);
    try expectEqual(Range{ .start = 0x10, .end = 0x100 }, testee.ranges[0]);
    // Subtract right.
    try testee.remove(.{ .start = 0x100, .end = 0x100 });
    try expect(testee.used == 4);
    try expectEqual(Range{ .start = 0x10, .end = 0xff }, testee.ranges[0]);
    try testee.remove(.{ .start = 0xf1, .end = 0x100 });
    try expect(testee.used == 4);
    try expectEqual(Range{ .start = 0x10, .end = 0xf0 }, testee.ranges[0]);
    // Subtract multiple contain.
    try testee.remove(.{ .start = 0x350, .end = 0x800 });
    try expect(testee.used == 2);
    // Subtract contain.
    try testee.remove(.{ .start = 0x20, .end = 0x30 });
    try expect(testee.used == 3);
    try expectEqual(Range{ .start = 0x10, .end = 0x1f }, testee.ranges[0]);

    testee = RangeSet(4).init;
    try testee.insert(.{ .start = 0x0, .end = 0xf });
    try testee.insert(.{ .start = 0x20, .end = 0x2f });
    try expect(testee.used == 2);
    // Insert range which joins other two.
    try testee.insert(.{ .start = 0x10, .end = 0x1f });
    try expect(testee.used == 1);
    try expectEqual(Range{ .start = 0x0, .end = 0x2f }, testee.ranges[0]);

    // Zero sized allocation.
    try expectEqual(null, testee.alloc(0, 4));
    // Invalid alignment.
    try expectEqual(null, testee.alloc(4, 3));
    // Valid allocations.
    try expectEqual(0x0, testee.alloc(0x10, 8));
    try expectEqual(0x10, testee.alloc(0x10, 8));
    try expectEqual(0x20, testee.alloc(1, 1));
    try expectEqual(0x21, testee.alloc(1, 1));
    // Allocation which has front padding.
    try expectEqual(0x24, testee.alloc(4, 4));
    // Consume remaining memory.
    try expectEqual(0x28, testee.alloc(8, 4));
    try expect(testee.used == 0);
}
