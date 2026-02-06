# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

include ../utils.mk

UI   ?= n
UI-y := -serial stdio
UI-n := -nographic

ARGS-y      += $(UI-$(UI))
ARGS-$(DBG) += -S -s
ARGS-$(KVM) += -enable-kvm -cpu host,+vmx

build: $(B)/boot.bin check-entry-boot check-mbr-boot

$(B)/boot.elf: $(B)/mbr-32.o $(B)/main-32.o

# Run on x86_64 to have certain cpu features available.
run: $(B)/boot.bin
	qemu-system-x86_64 -drive file=$<,format=raw $(ARGS-y)
