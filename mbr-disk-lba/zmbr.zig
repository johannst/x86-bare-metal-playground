// Frambuffer limits.
const COLS = 80;
const ROWS = 25;

// Frambuffer cursor.
var col: u16 = 0;
var row: u16 = 0;

// Frambuffer.
const fb: []u16 = @as([*]u16, @ptrFromInt(0xB8000))[0 .. COLS * ROWS];

/// Clear screen (all black).
fn clear_screen() void {
    for (fb) |*ch| {
        ch.* = 0;
    }
}

/// Draw string to current cursor position.
fn puts(str: []const u8) void {
    // Each framebuffer entry in text mode is 16bit wide.
    //      [15] blink
    //   [14:12] bg color (3 bit)
    //   [11: 8] fg color (4 bit)
    //   [ 7: 0] ascii character
    // https://en.wikipedia.org/wiki/VGA_text_mode
    for (str) |ch| {
        if (ch == '\n') {
            col = 0;
            row += 1;
        } else {
            const pos = (row * COLS + col);
            // bg - black; fg - white;
            fb[pos] = @as(u16, 15) << 8 | ch;
            col += 1;
        }
        if (col == COLS) {
            row += 1;
            if (row == ROWS) {
                row = 0;
            }
        }
    }
}

// kmain should be "callconv(.naked)", once issue is fixed.
// https://github.com/ziglang/zig/issues/18183
export fn kmain() noreturn {
    clear_screen();

    // Print first bytes of LBA block 1 we loaded from disk (sector 2).
    const lba1: []const u8 = @as([*]const u8, @ptrFromInt(0x7e00))[0..4];
    puts("lba1: ");
    puts(lba1);
    puts("\n");

    // Print first bytes of LBA block 2 we loaded from disk (sector 3).
    const lba2: []const u8 = @as([*]const u8, @ptrFromInt(0x8000))[0..4];
    puts("lba2: ");
    puts(lba2);
    puts("\n");

    while (true) {
        asm volatile ("hlt");
    }
}
