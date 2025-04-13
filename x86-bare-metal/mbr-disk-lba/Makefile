O := BUILD

all: dump_elf dump_bin

$(O)/boot: $(O)/boot.elf
	# MBR 512 bytes (sector 1 - lba 0)
	objcopy -O binary $< $@
	# Craft 512 bytes (sector 2 - lba 1)
	printf "aaaa" >> $@
	dd if=/dev/zero bs=1 count=508 >> $@
	# Craft 512 bytes (sector 3 - lba 2)
	printf "bbbb" >> $@
	dd if=/dev/zero bs=1 count=508 >> $@

$(O)/boot.elf: mbr.ld $(O)/mbr.o $(O)/zmbr.o
	ld -o $@ -nostdlib -T $^

$(O)/mbr.o: mbr.S | $(O)
	gcc -m32 -c -o $@ -ffreestanding mbr.S

$(O)/zmbr.o: zmbr.zig | $(O)
	zig build-obj -fno-strip -femit-bin=$@ -target x86-freestanding-none -O ReleaseSmall $<

clean:
	$(RM) -r $(O)

$(O):
	mkdir -p $(O)

dump_elf: $(O)/boot.elf
	@#objdump -Mintel --disassemble=kmain --visualize-jumps=extended-color $<
	readelf -W -l $<
	size $<
	size $< | awk '/$(notdir $<)/ { print "MBR utilization " $$1/512 "%" }'

dump_bin: $(O)/boot
	hexdump -C $<

run: $(O)/boot
	qemu-system-i386 -hda $< $(QEMU_ARGS)
