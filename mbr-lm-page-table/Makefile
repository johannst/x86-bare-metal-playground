# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

# CPU-64 := generic -> misses see support
# compiler-rt requires sse support
ZFLAGS = -fno-compiler-rt

include ../utils.mk

UI ?= y

DISP-y      = -serial stdio
DISP-n      = -nographic
ARGS-$(DBG) = -S -s
ARGS-y      = $(DISP-$(UI))

build: $(B)/boot-64.bin check-rangeset check-entry-boot-64 check-mbr-boot-64

$(B)/boot-64.elf: $(B)/mbr-64.o $(B)/main-64.o $(B)/rt-64.o

run: $(B)/boot-64.bin
	qemu-system-x86_64 -drive file=$<,format=raw $(ARGS-y)

check-rangeset: shared/rangeset.zig
	$(call vcmd,CHECK-RSET,$<,zig test $< -O Debug)
