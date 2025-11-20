// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

/// Execute cpuid instruction, returning (eax, ebx, ecx, edx).
inline fn cpuid(in_eax: u32, in_ecx: u32) struct { u32, u32, u32, u32 } {
    var eax: u32 = undefined;
    var ebx: u32 = undefined;
    var ecx: u32 = undefined;
    var edx: u32 = undefined;

    asm volatile ("cpuid"
        : [eax] "={eax}" (eax),
          [ebx] "={ebx}" (ebx),
          [ecx] "={ecx}" (ecx),
          [edx] "={edx}" (edx),
        : [in_eax] "{eax}" (in_eax),
          [in_ecx] "{ecx}" (in_ecx),
    );

    return .{ eax, ebx, ecx, edx };
}

pub const Features = packed struct {
    vmx: bool,

    syscall: bool,
    nx: bool,
    gb_pages: bool,
    lm: bool,

    paddr_bits: u8,
    vaddr_bits: u8,
};

/// Compute cpu features.
pub fn features() Features {
    var f = @import("std").mem.zeroes(Features);
    var eax: u32 = undefined;
    var ebx: u32 = undefined;
    var ecx: u32 = undefined;
    var edx: u32 = undefined;

    const bit = struct {
        fn bit(val: u32, idx: u5) bool {
            return (val >> idx) & 1 == 1;
        }
    }.bit;

    const max_basic, _, _, _ = cpuid(0, 0);
    const max_extended, _, _, _ = cpuid(0x8000_0000, 0);

    if (0x1 <= max_basic) {
        eax, ebx, ecx, edx = cpuid(0x1, 0);
        f.vmx = bit(ecx, 5);
    }
    if (0x8000_0001 <= max_extended) {
        eax, ebx, ecx, edx = cpuid(0x8000_0001, 0);
        f.syscall = bit(edx, 11);
        f.nx = bit(edx, 20);
        f.gb_pages = bit(edx, 26);
        f.lm = bit(edx, 29);
    }
    if (0x8000_0008 <= max_extended) {
        eax, ebx, ecx, edx = cpuid(0x8000_0008, 0);
        f.paddr_bits = @truncate((eax >> 0) & 0xff);
        f.vaddr_bits = @truncate((eax >> 8) & 0xff);
    }

    return f;
}
