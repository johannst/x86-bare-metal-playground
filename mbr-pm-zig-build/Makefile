# SPDX-License-Identifier: MIT
#
# Copyright (c) 2026, Johannes Stoelp <dev@memzero.de>

include ../utils.mk

UI   ?= y
UI-y := -serial stdio
UI-n := -nographic

ARGS-y      += $(UI-$(UI))
ARGS-$(DBG) += -S -s

# Extended verbosity for zig build.
VERBOSE-2 += --verbose

build: $(B)/boot.elf check-entry-boot check-mbr-boot

$(B)/boot.elf: build.zig mbr.S mbr.ld
	$(call vcmd,ZIG_BUILD,.,zig build --prefix-exe-dir $(B) --cache-dir $(B) $(VERBOSE-$(V)))

run: $(B)/boot.bin
	qemu-system-i386 -drive file=$<,format=raw $(ARGS-y) -m 2G -vga std
