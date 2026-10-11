// SPDX-License-Identifier: MIT
//
// Copyright (c) 2026, Johannes Stoelp <dev@memzero.de>

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .none,
        // Cpu w/o hard float support.
        .cpu_model = .{ .explicit = &std.Target.x86.cpu.i386 },
    });

    const exe = b.addExecutable(.{
        .name = "boot.elf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("stage2.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });
    exe.addAssemblyFile(b.path("mbr.S"));
    exe.linker_script = b.path("mbr.ld");
    exe.entry = .{ .symbol_name = "rm_entry" };

    b.installArtifact(exe);
}
