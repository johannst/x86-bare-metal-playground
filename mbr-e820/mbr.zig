const bios = @import("bios.zig");

// -- ENTRY POINT ---------------------------------------------------------------

export fn _entry() linksection(".boot") callconv(.Naked) noreturn {
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
    dump_memmap();

    while (true) {
        asm volatile ("hlt");
    }
}

// -- UTILS ---------------------------------------------------------------------

fn dump_memmap() void {
    // Keep track of continuatation code.
    var off: u32 = 0;
    // Accumulated free/usable memory.
    var mem: u64 = 0;

    // Iterate over E820 entries.
    while (bios.e820(off)) |entry| : (off = entry.ebx) {
        puts_hex(entry.e820.base);
        bios.putc('-');
        puts_hex(entry.e820.size);
        bios.putc('-');
        puts_hex(entry.e820.kind);
        bios.putc('-');
        puts_hex(entry.e820.attr);
        bios.putc('\n');

        // Accumulate free, useable memory.
        if (entry.e820.kind == 1 and entry.e820.attr == 1) {
            mem += entry.e820.size;
        }

        // All E820 entries retrieved, continuing would start from the beginning.
        if (entry.ebx == 0) {
            break;
        }
    }

    // Report total free memory in MBs.
    bios.putc('m');
    bios.putc('=');
    puts_hex(mem / 1024 / 1024);
}

fn puts(str: []const u8) void {
    for (str) |c| {
        bios.putc(c);
    }
}

fn puts_hex(init_val: u64) void {
    if (init_val == 0) {
        bios.putc('0');
        return;
    }

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
