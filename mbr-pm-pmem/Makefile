# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

include ../utils.mk

ARGS-$(DBG) = -S -s
ARGS-$(CON) = -nographic

build: $(B)/boot-32.bin check-offset check-rangeset check-entry-boot-32 check-mbr-boot-32

$(B)/boot-32.elf: $(B)/mbr-32.o $(B)/bios_call-32.o $(B)/stage2-32.o

run: $(B)/boot-32.bin
	qemu-system-i386 -drive file=$<,format=raw $(ARGS-y) -m 2G

check-offset: bios_call.zig
	$(call vcmd,CHECK-OFFSET,$<,zig test $< -O Debug -lc -I.)

check-rangeset: shared/rangeset.zig
	$(call vcmd,CHECK-RSET,$<,zig test $< -O Debug)
