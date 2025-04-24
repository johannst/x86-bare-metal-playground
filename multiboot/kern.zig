const fmt = @import("std").fmt;
const dbg = @import("std").debug;

const vga = @import("vga.zig");
const mb = @import("mb.zig");

export const mbhdr align(4) linksection(".mbhdr") = mb.HEADER;

var KERNEL_STACK: [32 * 4096]u8 align(16) = undefined;

export fn _start() align(16) linksection(".text.boot") callconv(.naked) noreturn {
    @setRuntimeSafety(false);
    asm volatile (
        \\mov %%eax, %%esp
        // Push paddr of multiboot info structure on ask (per abi first integer argument to the fn).
        \\pushl %%ebx
        \\call kmain
        \\1: hlt
        \\jmp 1b
        :
        : [top] "{eax}" (@intFromPtr(&KERNEL_STACK) + KERNEL_STACK.len),
    );
}

export fn kmain(ebx: u32) void {
    var con = vga.vga(10, 0).init;
    con.puts("Booting into kmain()\n\n");

    mb.formatBootinfo(con.writer(), mb.bootinfo(ebx)) catch {};

    dbg.panic("{s}:{}:{s}: done...", .{ @src().file, @src().line, @src().fn_name });
}

// -- PANIC HANDLER -------------------------------------------------------------

pub const panic = dbg.FullPanic(panicHandler);

fn panicHandler(msg: []const u8, first_trace_addr: ?usize) noreturn {
    _ = first_trace_addr;

    var con = vga.vga(11, 0).init;
    fmt.format(con.writer(), "\nPANIC: {s}\n", .{msg}) catch {};

    while (true) {
        asm volatile ("hlt");
    }
}
