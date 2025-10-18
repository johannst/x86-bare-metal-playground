// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

const std = @import("std");
const bios = @import("bios_call.zig");

pub export fn stage2_entry() void {
    var regs = std.mem.zeroes(bios.RegisterState);
    for ("hello from stage2 bootloader") |c| {
        // Int 10/AH=0Eh - Teletype output
        // AL = character to write
        //
        // https://www.ctyme.com/intr/rb-0106.htm
        regs.eax = @as(u32, 0xe00) | c;
        bios.bios_call(0x10, &regs);
    }
}
