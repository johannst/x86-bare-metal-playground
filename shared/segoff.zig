// SPDX-License-Identifier: MIT
//
// Copyright (c) 2026, Johannes Stoelp <dev@memzero.de>

pub const SegOff = extern struct {
    off: u16,
    seg: u16,

    pub fn linear(self: SegOff) u32 {
        return (@as(u32, self.seg) << 4) + self.off;
    }

    pub fn from(ptr: usize, len: usize) ?SegOff {
        if (len == 0)
            return null;
        if (ptr & 0xfff0_0000 != 0)
            return null;
        if ((ptr + len - 1) & 0xfff0_0000 != 0)
            return null;
        return .{
            .off = @truncate(ptr),
            .seg = @truncate((ptr >> 16) << 12),
        };
    }
};

comptime {
    const assert = @import("std").debug.assert;
    assert(SegOff.from(0x0000_0000, 0) == null);
    assert(SegOff.from(0x8000_0000, 1) == null);
    assert(SegOff.from(0x000f_ffff, 2) == null);
    assert(SegOff.from(0x000f_ffff, 1).?.linear() == 0x000f_ffff);
    assert(SegOff.from(0x000f_ffff, 1).?.off == 0x000_ffff);
    assert(SegOff.from(0x000f_ffff, 1).?.seg == 0x000_f000);
}
