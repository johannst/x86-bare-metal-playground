include ../utils.mk

# Need to squeeze the binary a bit more :^)
ZFLAGS := -fomit-frame-pointer

build: $(B)/boot.bin check-entry-boot check-mbr-boot

$(B)/boot.elf: $(B)/mbr-16.o

run: $(B)/boot.bin
	qemu-system-i386 -drive file=$<,format=raw -nographic
