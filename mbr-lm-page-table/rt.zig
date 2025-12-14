// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

export fn memmove(dst: ?[*]u8, src: ?[*]const u8, len: usize) callconv(.c) ?[*]u8 {
    if (@intFromPtr(dst.?) < @intFromPtr(src.?)) {
        for (0..len) |i| {
            dst.?[i] = src.?[i];
        }
    } else {
        for (0..len) |i| {
            dst.?[len - 1 - i] = src.?[len - 1 - i];
        }
    }
    return dst;
}

export fn memcpy(noalias dst: ?[*]u8, noalias src: ?[*]const u8, len: usize) callconv(.c) ?[*]u8 {
    for (0..len) |i| {
        dst.?[i] = src.?[i];
    }
    return dst;
}

export fn memset(dst: ?[*]u8, c: u8, len: usize) callconv(.c) ?[*]u8 {
    for (0..len) |i| {
        dst.?[i] = c;
    }
    return dst;
}
