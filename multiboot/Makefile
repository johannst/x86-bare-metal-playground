include ../utils.mk

# Overwrite default linker script.
LDSCRIPT := kern.ld

$(B)/disk.img: $(B)/kern.elf grub check-mbhdr check-sse
	mkdir -p $(B)/iso/boot
	rsync -rav $(filter-out check-%,$^) $(B)/iso/boot
	grub-mkrescue -o $@ $(B)/iso -d /usr/lib/grub/i386-pc --modules="biosdisk part_msdos multiboot" 2> $(B)/grub.txt || { cat $(B)/grub.txt; exit 1; }

$(B)/kern.elf: $(B)/kern-32.o

check-mbhdr: $(B)/kern.elf
	$(call vcmd, CHECK-MBHDR,$<,xxd -d -e -c4 $< | awk -f scripts/check_mbhdr.awk)

check-sse: $(B)/kern.elf
	$(call vcmd, CHECK-SSE,$<,objdump -d $< | awk -f scripts/check_sse.awk)

run: $(B)/kern.elf
	qemu-system-i386 -kernel $< -append mode=raw-elf

run-img: $(B)/disk.img
	qemu-system-i386 -drive file=$<,format=raw
