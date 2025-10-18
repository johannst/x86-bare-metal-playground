// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

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

    pub fn cf(self: *const @This()) bool {
        return (self.eflags & 1) != 0;
    }
};

/// Invoke a bios call defined by the interrupt number `irq` and the
/// register state in `regs`. The register parameter is an inout
/// parameter, as it will be updated to hold the register state directly
/// after the bios call.
/// This can only be used during early boot as it assumes a given
/// environment, see bios_call.S for more information.
pub extern fn bios_call(irq: u8, regs: *RegisterState) void;

test "offset" {
    const c = @cImport({
        @cDefine("ASM_INCLUDE_ONLY", "1");
        @cInclude("bios_call.S");
    });
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
