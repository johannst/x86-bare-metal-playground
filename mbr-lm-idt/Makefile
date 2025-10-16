# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

# CPU-64 := generic -> misses see support
# compiler-rt requires sse support
ZFLAGS = -fno-compiler-rt

include ../utils.mk

ARGS-y = -S -s

build: $(B)/boot-64.bin check-entry-boot-64 check-mbr-boot-64

$(B)/boot-64.elf: $(B)/mbr-64.o

run: $(B)/boot-64.bin
	qemu-system-x86_64 -drive file=$<,format=raw $(ARGS-$(DBG)) #-nographic
