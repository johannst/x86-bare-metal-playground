# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

include ../utils.mk

ARGS-y = -S -s

build: $(B)/boot.bin check-entry-boot check-mbr-boot

$(B)/boot.elf: $(B)/mbr-16.o

run: $(B)/boot.bin
	qemu-system-i386 -drive file=$<,format=raw $(ARGS-$(DBG)) -nographic
