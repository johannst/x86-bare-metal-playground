# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

include ../utils.mk

ARG-$(DBG) += -S -s
ARG-$(CON) += -nographic
ARG-$(KVM) += -enable-kvm -cpu host,+vmx

build: $(B)/boot.bin check-entry-boot check-mbr-boot

$(B)/boot.elf: $(B)/mbr-32.o $(B)/main-32.o

# Run on x86_64 to have certain cpu features available.
run: $(B)/boot.bin
	qemu-system-x86_64 -drive file=$<,format=raw $(ARG-y)
