# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

# TODO: Find a better way to compute the project root.
B := $(abspath ..)/build/$(notdir $(CURDIR))

LDSCRIPT ?= mbr.ld

# -- COMPILE FUNCS -------------------------------------------------------------

# Zig compiler command.
# Arguments: 1-bitness(16/32) 2-outfile 3-infile
#
# When building the kernel we explicitly let the zig compiler emit code for a
# very old cpu. This way we ensure it does not emit any sse instructions, which
# first need to be enabled before the can be used (setting up ctrl registers and
# sse state).
TARGET-16 := x86-freestanding-code16
TARGET-32 := x86-freestanding-none
TARGET-64 := x86_64-freestanding-none
CPU-16 := i386
CPU-32 := i386
CPU-64 := generic
zc = zig build-obj -target $(TARGET-$(1)) -mcpu $(CPU-$(1)) -O ReleaseSmall -fno-unwind-tables -fno-strip $(ZFLAGS) $(ZCFLAGS) -femit-bin=$(2) $(3)

# Assembler command.
# Arguments: 1-outfile 2-infile
as = $(CC) -c -m$(1) -ffreestanding -o $(2) $(3)

# Linker command.
# Arguments: 1-outfile 2-infile(s)
ld = zig build-exe -target $(TARGET-$(1)) -mcpu $(CPU-$(1)) -O ReleaseSmall -fno-unwind-tables -fno-strip $(ZFLAGS) -fno-entry --script $(LDSCRIPT) -femit-bin=$(2) $(3)

# -- UTILITY FUNCS -------------------------------------------------------------

# Create parent directory chain of file path.
# Arguments: 1-filepath
mk = @mkdir -p $(dir $(1))

# Echo short (V=0) or verbose (V=1) command and execute command.
# Arguments: 1-short-cmd-name 2-short-file-name 3-real-command
vcmd = @ $(if $(filter-out 0,$(V)),printf "$(3)\n",printf "%-12s %s\n" "$(1)" "$(notdir $(2))") ; $(3)

# -- BUILD RULES ---------------------------------------------------------------
#
# The following provide some default rules which can be used in down-stream
# Makefiles to assemble, compile and link.

# Assemble or compile files for 16-bit target.
# Add "$(B)/foo-16.o" dependency to (i) assemble foo.S or (ii) compile %.zig.
$(B)/%-16.o: %.S
	$(call mk,$@)
	$(call vcmd,AS,$@,$(call as,16,$@,$<))
$(B)/%-16.o: %.zig
	$(call mk,$@)
	$(call vcmd,ZIG,$@,$(call zc,16,$@,$<))

# Assemble or compile files for 32-bit target.
# Add "$(B)/foo-32.o" dependency to (i) assemble foo.S or (ii) compile %.zig.
$(B)/%-32.o: %.S
	$(call mk,$@)
	$(call vcmd,AS,$@,$(call as,32,$@,$<))
$(B)/%-32.o: %.zig
	$(call mk,$@)
	$(call vcmd,ZIG,$@,$(call zc,32,$@,$<))

# Assemble or compile files for 64-bit target.
# Add "$(B)/foo-64.o" dependency to (i) assemble foo.S or (ii) compile %.zig.
$(B)/%-64.o: %.S
	$(call mk,$@)
	$(call vcmd,AS,$@,$(call as,64,$@,$<))
$(B)/%-64.o: %.zig
	$(call mk,$@)
	$(call vcmd,ZIG,$@,$(call zc,64,$@,$<))

# Link an elf file.
# The user must provide the dependencies.
$(B)/%.elf:
	$(call vcmd,LD,$@,$(call ld,32,$@,$^))

$(B)/%-64.elf:
	$(call vcmd,LD,$@,$(call ld,64,$@,$^))

# Produce binary from elf file.
$(B)/%.bin: $(B)/%.elf
	$(call vcmd,OBJCOPY,$@,objcopy -O binary $< $@)

# -- CHECK RULES ---------------------------------------------------------------

# Check if entry point in an elf file is at 0x7c00.
check-entry-%: $(B)/%.elf
	$(call vcmd,CHECK-ENTRY,$<,readelf -h $< | grep -q 'Entry point address:\s*0x7c00$$')

# Check MBR magic in a binary.
check-mbr-%: $(B)/%.bin
	$(call vcmd,CHECK-MBR,$<,xxd -d -l 2 -s 510 $< | grep -q "510: 55aa")
