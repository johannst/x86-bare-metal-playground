# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

include ../utils.mk

ARGS-y = -S -s

build: $(B)/boot-32.bin check-offset check-entry-boot-32 check-mbr-boot-32

$(B)/boot-32.elf: $(B)/mbr-32.o $(B)/bios_call-32.o $(B)/stage1-32.o $(B)/stage2-32.o

# qemu config:
# - smp to see some more local apics in the MADT acpi table.
# - q35 rather than legacy ibm-pc, due to usage of MCFG acpi table, which lists
#   non-hotplug pci devies.
# - nic just to add some virtio pci device
#
# Resize raw disk, as q35 does not boot MBR sector if disk is "too" small.
# Value choosen by doubling size until it booted.
run: $(B)/boot-32.bin | build
	truncate -s 524288 $<
	qemu-system-i386 -drive file=$<,format=raw $(ARGS-$(DBG)) -smp 4 -M q35 -nic user,model=virtio-net-pci -nographic

check-offset: bios_call.zig
	$(call vcmd,CHECK-OFFSET,$<,zig test $< -O Debug -lc -I.)

symbol:
	addr2line -e $(B)/boot-32.elf -a -p -f $(A)
