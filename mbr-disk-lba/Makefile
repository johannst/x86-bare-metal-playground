# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

include ../utils.mk

build: extend-img check-entry-boot check-mbr-boot

extend-img: $(B)/boot.bin
	# Craft 512 bytes (sector 2 - lba 1)
	printf "aaaa" >> $<
	dd if=/dev/zero bs=1 count=508 status=none >> $<
	# Craft 512 bytes (sector 3 - lba 2)
	printf "bbbb" >> $<
	dd if=/dev/zero bs=1 count=508 status=none >> $<

$(B)/boot.elf: $(B)/mbr-16.o $(B)/zmbr-32.o

run: extend-img
	qemu-system-i386 -drive file=$(B)/boot.bin,format=raw
