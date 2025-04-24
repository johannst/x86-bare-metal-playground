const COLS = 80;
const ROWS = 25;

/// Clear screen (all black).
fn clear_screen(video: []u16) void {
    for (video) |*ch| {
        ch.* = 0;
    }
}

/// Draw the color palette.
fn draw_palette(video: []u16) void {
    // Each framebuffer entry in text mode is 16bit wide.
    //      [15] blink
    //   [14:12] bg color (3 bit)
    //   [11: 8] fg color (4 bit)
    //   [ 7: 0] ascii character
    //
    // https://en.wikipedia.org/wiki/VGA_text_mode

    // Print each bg / fg combination once.
    for (video, 0..0x80) |*ch, i| {
        ch.* = @as(u16, @truncate(i)) << 8 | 'a';
    }
}

// kmain should be "callconv(.naked)", once issue is fixed.
// https://github.com/ziglang/zig/issues/18183
export fn kmain() noreturn {
    // Take a slice to VGA video memory (mode 3h text mode 80x25).
    const video: []u16 = @as([*]u16, @ptrFromInt(0xB8000))[0 .. COLS * ROWS];

    clear_screen(video);
    draw_palette(video);

    while (true) {
        asm volatile ("hlt");
    }
}
