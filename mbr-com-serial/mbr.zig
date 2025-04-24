const Com = @import("com.zig").Com;

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

// Global access to COM0.
var com0: ?Com = null;

// main should be "callconv(.naked)", once issue is fixed.
// https://github.com/ziglang/zig/issues/18183
export fn main() noreturn {
    com0 = com0 orelse Com.init(Com.COM1);
    com0.?.puts("\n\nBooted into mbr.zig\n");

    @panic("end reached, crashing kernel");
}

pub const panic = @import("std").debug.FullPanic(panicHandler);

fn panicHandler(msg: []const u8, first_trace_addr: ?usize) noreturn {
    _ = first_trace_addr;

    com0 = com0 orelse Com.init(Com.COM1);
    com0.?.puts("\nPANIC: ");
    com0.?.puts(msg);
    com0.?.puts("\n");

    while (true) {
        asm volatile ("hlt");
    }
}
