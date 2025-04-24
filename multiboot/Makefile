O := BUILD

# Build a legacy bios only boot disk.
$(O)/disk.img: $(O)/kern grub
	mkdir -p $(O)/iso/boot
	rsync -rav $^ $(O)/iso/boot
	grub-mkrescue -o $@ $(O)/iso -d /usr/lib/grub/i386-pc --modules="biosdisk part_msdos multiboot"

# When building the kernel we explicitly let the zig compiler emit code for a
# very old cpu.  This way we ensure it does not emit any sse instructions, which
# first need to be enabled before the can be used (setting up ctrl registers and
# sse state).
$(O)/kern: kern.ld kern.zig
	mkdir -p $(O)
	zig build-exe -fno-unwind-tables -femit-bin=$@ -target x86-freestanding-none -mcpu i386 -O Debug -fno-strip --script $^
	xxd -d -e -c4 $@ | awk -f scripts/check_mbhdr.awk
	objdump -d $@ | awk -f scripts/check_sse.awk

clean:
	$(RM) -r $(O)

run: $(O)/kern
	qemu-system-i386 -kernel $< -append mode=raw-elf

run-img: $(O)/disk.img
	qemu-system-i386 -hda $<
