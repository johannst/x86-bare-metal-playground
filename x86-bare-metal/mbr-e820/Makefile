O := BUILD

COMMON_FLAGS := -fno-unwind-tables -fno-strip -target x86-freestanding-code16 -O ReleaseSmall -mcpu=i386 -fomit-frame-pointer

$(O)/boot: $(O)/boot.elf | check_ep dump_info
	objcopy -O binary $< $@

$(O)/boot.elf: mbr.ld mbr.zig | $(O)
	zig build-exe -femit-bin=$@ $(COMMON_FLAGS) -fno-entry --script $^

clean:
	$(RM) -r $(O)

$(O):
	mkdir -p $(O)

# Check entry point is exactly at 0x7c00.
check_ep: $(O)/boot.elf
	readelf -h $< | awk '/Entry point address:/ { print $$4 }' | grep 0x7c00 >& /dev/null

# Dump some debug info (disasm, elf load segments, code size).
dump_info: $(O)/boot.elf
	objdump -Mintel -m i8086 --disassemble --visualize-jumps=extended-color $<
	readelf -W -l $<
	size $<
	size $< | awk '/$(notdir $<)/ { print "MBR utilization " $$1/512 "%" }'

run: $(O)/boot
	qemu-system-i386 -hda $< $(QEMU_ARGS)
