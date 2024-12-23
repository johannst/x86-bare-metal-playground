O := BUILD

$(O)/boot: $(O)/boot.elf | dump_info
	objcopy -O binary $< $@

$(O)/boot.elf: mbr.ld $(O)/mbr.o $(O)/zmbr.o
	ld -o $@ -nostdlib -T $^

$(O)/mbr.o: mbr.S | $(O)
	gcc -m32 -c -o $@ -ffreestanding mbr.S

$(O)/zmbr.o: zmbr.zig | $(O)
	zig build-obj -femit-bin=$@ -target x86-freestanding-none -O ReleaseSmall $<

clean:
	$(RM) -r $(O)

$(O):
	mkdir -p $(O)

dump_info: $(O)/boot.elf
	objdump -Mintel --disassemble=kmain --visualize-jumps=extended-color $<
	readelf -W -l $<
	size $<
	size $< | awk '/$(notdir $<)/ { print "MBR utilization " $$1/512 "%" }'

run: $(O)/boot
	qemu-system-i386 -hda $< $(QEMU_ARGS)
