// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

const COLS = 320;
const ROWS = 200;

/// Draw the color palette.
/// One color per column, remaining columns are drawn black.
fn draw_palette(video: []u8) void {
    for (0..ROWS) |r| {
        for (0..COLS) |c| {
            if (c < 256) {
                video[COLS * r + c] = @truncate(c);
            } else {
                video[COLS * r + c] = 0;
            }
        }
    }
}

// kmain should be "callconv(.naked)", once issue is fixed.
// https://github.com/ziglang/zig/issues/18183
export fn kmain() noreturn {
    // Take a slice to 256-color VGA video memory (mode 13h graphic mode).
    const video: []u8 = @as([*]u8, @ptrFromInt(0xA0000))[0 .. COLS * ROWS];

    draw_palette(video);

    while (true) {
        asm volatile ("hlt");
    }
}
