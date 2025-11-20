// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

const cpu = @import("shared/cpu.zig");
const com = @import("shared/com.zig");

export fn main() noreturn {
    var com1 = com.Com.init(com.Com.COM1);
    var buf: [64]u8 = undefined;
    var iow = com1.writer(&buf);

    iow.interface.writeByte('\n') catch {};
    iow.print("{}", .{cpu.features()});
    iow.flush();

    while (true) {
        asm volatile ("hlt");
    }
}
