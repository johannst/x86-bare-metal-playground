// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

const std = @import("std");
const bios = @import("bios_call.zig");

export fn kmain() noreturn {
    var regs = std.mem.zeroes(bios.RegisterState);

    for ("hello from protected mode mbr") |c| {
        // Int 10/AH=0Eh - Teletype output
        // AL = character to write
        //
        // https://www.ctyme.com/intr/rb-0106.htm
        regs.eax = @as(u32, 0xe00) | c;
        bios.bios_call(0x10, &regs);
    }

    while (true) {}
}
