# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

include ../utils.mk

ARGS-y = -S -s

build: $(B)/boot-32.bin check-entry-boot-32 check-mbr-boot-32
	@od -tx1 -w1 -A d $< | grep cc | awk '{ printf "%-12s %.2f %\n", "MBR-USAGE", ($$1 / 510) * 100 }'

$(B)/boot-32.elf: $(B)/mbr-32.o

run: $(B)/boot-32.bin | build
	qemu-system-i386 -drive file=$<,format=raw $(ARGS-$(DBG))
