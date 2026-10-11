// SPDX-License-Identifier: MIT
//
// Copyright (c) 2026, Johannes Stoelp <dev@memzero.de>

const vga = @import("shared/vga.zig");

export fn stage2() void {
    var vgacon = vga.vga(.red, .black).init;
    vgacon.puts("hello from stage2");
}
