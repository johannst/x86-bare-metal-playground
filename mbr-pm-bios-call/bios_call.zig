// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

const c = @cImport({
    @cDefine("ASM_INCLUDE_ONLY", "1");
    @cInclude("bios_call.S");
});

pub const RegisterState = extern struct {
    eax: u32,
    ecx: u32,
    edx: u32,
    ebx: u32,
    esp: u32,
    ebp: u32,
    esi: u32,
    edi: u32,
    eflags: u32,

    fn cf(self: *const @This()) bool {
        return (self.eflags & 1) != 0;
    }
};

pub extern fn bios_call(irq: u8, regs: *RegisterState) void;

comptime {
    const assert = @import("std").debug.assert;
    assert(@offsetOf(RegisterState, "eax") == c.EAX_OFFSET);
    assert(@offsetOf(RegisterState, "ecx") == c.ECX_OFFSET);
    assert(@offsetOf(RegisterState, "edx") == c.EDX_OFFSET);
    assert(@offsetOf(RegisterState, "ebx") == c.EBX_OFFSET);
    assert(@offsetOf(RegisterState, "esp") == c.ESP_OFFSET);
    assert(@offsetOf(RegisterState, "ebp") == c.EBP_OFFSET);
    assert(@offsetOf(RegisterState, "esi") == c.ESI_OFFSET);
    assert(@offsetOf(RegisterState, "edi") == c.EDI_OFFSET);
    assert(@offsetOf(RegisterState, "eflags") == c.EFLAGS_OFFSET);
}
