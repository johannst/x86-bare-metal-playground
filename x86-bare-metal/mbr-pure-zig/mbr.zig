const bios = @import("bios.zig");

// -- ENTRY POINT ---------------------------------------------------------------

export fn _entry() linksection(".boot") callconv(.naked) noreturn {
    asm volatile (
    // Disable interrupts.
        \\cli
        // Clear segment selectors.
        \\xor %%ax, %%ax
        \\mov %%ax, %%ds
        \\mov %%ax, %%es
        \\mov %%ax, %%ss
        \\mov %%ax, %%fs
        \\mov %%ax, %%gs
        \\mov $0x7c00, %sp
        // Long jump to set cs to 0x0000, as some BIOSes load the MBR
        // to either 07c0:0000 or 0000:7c000.
        \\ljmp $0x0, $main
    );
}

// -- MAIN ----------------------------------------------------------------------

// main should be "callconv(.naked)", once issue is fixed.
// https://github.com/ziglang/zig/issues/18183
export fn main() noreturn {
    for (0..255) |i| {
        if (i < bios.ROWS) {
            bios.set_pos(@truncate(i));
        } else {
            // Once we reach the bottom of the screen start scrolling.
            bios.scroll_up();
            bios.set_pos(bios.ROWS - 1);
        }
        puts_dec(i + 1);
        bios.putc(' ');
        puts_hex(i + 1);
        bios.putc(' ');
        bios.putc(@truncate('a' + (i % 26)));
        bios.putc(@truncate('a' + (i % 26)));
        waste_time();
    }
    puts("\ndone");

    while (true) {
        asm volatile ("hlt");
    }
}

// -- UTILS ---------------------------------------------------------------------

fn puts(str: []const u8) void {
    for (str) |c| {
        bios.putc(c);
    }
}

fn puts_dec(init_val: u32) void {
    var val = init_val;
    var buf: [32]u8 = undefined;
    var idx = buf.len;

    while (val > 0 and idx != 0) : (val /= 10) {
        idx -= 1;
        buf[idx] = @as(u8, @truncate(val % 10)) + '0';
    }
    puts(buf[idx..]);
}

fn puts_hex(init_val: u32) void {
    var val = init_val;
    var buf: [32]u8 = undefined;
    var idx = buf.len;

    while (val > 0 and idx != 0) : (val /= 16) {
        idx -= 1;
        const digit = switch (@as(u8, @truncate(val % 16))) {
            0...9 => |d| '0' + d,
            10...15 => |d| 'a' + d - 10,
            else => '?',
        };
        buf[idx] = digit;
    }
    puts(buf[idx..]);
}

fn rdtsc() u32 {
    return asm volatile ("rdtsc"
        : [eax] "={eax}" (-> u32),
        :
        : "edx"
    );
}

fn waste_time() void {
    const start = rdtsc();
    var now = start;
    var idx: usize = 0;
    while (now - start < (1 << 28)) : (idx += 1) {
        if (idx == 10_000) {
            now = rdtsc();
            idx = 0;
        }
    }
}
