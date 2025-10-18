# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

include ../utils.mk

ARGS-y = -S -s

build: $(B)/boot-32.bin check-offset check-entry-boot-32 check-mbr-boot-32

$(B)/boot-32.elf: $(B)/mbr-32.o $(B)/bios_call-32.o $(B)/main-32.o

run: $(B)/boot-32.bin
	qemu-system-i386 -drive file=$<,format=raw $(ARGS-$(DBG))

check-offset: bios_call.zig
	$(call vcmd,CHECK-OFFSET,$<,zig test $< -O Debug -lc -I.)
