# x86 bare metal playground

This repository mainly serves as playground for bare metal x86 experiments,
testing different assembly flavors and learning bare metal zig.

One can just execute `make run` in each sub-directory to build and run the given
experiment. This assumes that all required tools are installed locally.

For convenience, the [`flake.nix`](flake.nix) provides a development environment,
which also documents the required tools.
```sh
# Drop into interactive shell.
nix develop

# Run the multiboot experiment for example.
nix develop --command make -C multiboot run

# Drop into a  pure interactive development shell.
nix develop -i -k USER -k HOME -k DISPLAY
```

The sub-folders of the experiments follow a naming scheme with the following
meanings.

- `mbr`: Build a [*master boot record (MBR)*](#mbr) boot sector which can be
  booted from legacy bios.
- `rm`: The experiment runs fully in 16-bit *real mode*.
- `pm`: The experiment enters 32-bit *protected mode*. This requires at least to
  setup a *global descriptor table (GDT)*.
- `lm`: The experiment enters 64-bit *long mode*. This requires at least to setup
  a *GDT* as well as *paging*.

Keypoints of each experiment:

- [`multiboot/`](multiboot): Build a kernel with multiboot 1 header and boot
  into it using grub as bootloader.
- [`mbr-rm-com-serial/`](mbr-rm-com-serial): Implement an *8250* compatible uart
  driver and write to *COM1* serial port purely in real mode.
- [`mbr-rm-e820-asm/`](mbr-rm-e820-asm): Retrieve the system memory map using
  the [*E820*](http://www.ctyme.com/intr/rb-1741.htm) bios call and format write
  it to the screen. This example is purely done in asm.
- [`mbr-rm-e820/`](mbr-rm-e820): Retrieve the system memory map using the
  [*E820*](http://www.ctyme.com/intr/rb-1741.htm) bios call and format write it
  to the screen.
- [`mbr-rm-textmode/`](mbr-rm-textmode): Use bios calls (interrupts) to write
  characters to the screen (vdeo text mode) and scroll up once last line is
  reached.
- [`mbr-pm-textmode/`](mbr-pm-textmode): Enter 32-bit *protected mode* and write
  to VGA mmio area (text video mode) to write character to the screen.
- [`mbr-pm-palette/`](mbr-pm-palette): Switch to VGA graphics video mode and
  enter 32-bit *protected mode*, then print the color palette of the selected
  graphics mode to the screen.
- [`mbr-pm-videomode/`](mbr-pm-videomode): Switch to VGA graphics video mode and
  enter 32-bit *protected mode*, then draw and animate some 2d and 3d shapes.
- [`mbr-pm-cpuid/`](mbr-pm-cpuid): Collect cpu features with the `cpuid`
  instruction.
- [`mbr-lm-enter-asm/`](mbr-lm-enter-asm): Enter 64-bit *long mode* by setting
  up an *idendity mapped* page table. This example is purely done in asm.
- [`mbr-pm-idt/`](mbr-pm-idt): Enter 32-bit *protected mode* and setup an
  *interrupt description table (IDT)*. Then trigger software interrupts using
  the `int` instruction.
- [`mbr-lm-idt/`](mbr-lm-idt): Enter 64-bit *long mode* and setup an *interrupt
  description table (IDT)*. Then trigger software interrupts using the `int`
  instruction.
- [`mbr-pm-disk-lba/`](mbr-pm-disk-lba): Use the [*extended read*](http://www.ctyme.com/intr/rb-0708.htm)
  bios call to read an additional sector from the disk into memory and access it
  afterwards.
- [`mbr-pm-bios-call/`](mbr-pm-bios-call): Implement a function which switches
  from 32-bit *protected mode* into 16-bit *real mode* to issue a bios call and
  then return back to protected mode. This can be used to make bios calls from
  protected mode.
- [`mbr-pm-2nd-stage/`](mbr-pm-2nd-stage): Load a second stage bootloader
  through bios calls made from protected mode.
- [`mbr-pm-2nd-stage-acpi/`](mbr-pm-2nd-stage-acpi): Load a second stage
  bootloader which parses the acpi root table and dumps the *MADT* and *MCFG*
  tables if available.
- [`mbr-pm-smp-boot-asm/`](mbr-pm-smp-boot-asm): Implement minimal example to
  boot multiple processors by sending INIT-SIPI *inter processor interrupts
  (IPI)* to the application processors (AP) from the bootstrap processor (BSP).
- [`mbr-pm-enter-user/`](mbr-pm-enter-user): Implement minimal example to
  transition between kernel (ring 0) and user (ring 3) privilege level in 32-bit
  protected mode.
- [`mbr-lm-enter-user/`](mbr-lm-enter-user): Implement minimal example to
  transition between kernel (ring 0) and user (ring 3) privilege level in 64-bit
  long mode.
- [`mbr-pm-pmem/`](mbr-pm-pmem): Implement basic physical memory manager (PMM)
  which allows to allocate physical memory. Initialize from free memory reported
  by the e820 bios call.
- [`mbr-lm-page-table/`](mbr-lm-page-table): Implement example which shows how
  to mondify a page table and map physical memory into virtual address space.

## MBR

The *master boot record (MBR)* is the first sector (512 byte) on a disk which
requires the following file magic at offset `510:0x55` and `511:0xaa`.

```sh
od -j510 -A d -t x1 build/mbr-pm-smp-boot-asm/boot-32.bin
# 0000510 55 aa
```

With legacy boot, the bios scans the boot medium for the MBR file magic and if
it matches, the MBR boot sector is loaded at address `0x7c00-0x7dff` and control
is transfered to it. At that point the processor is in 16-bit *real mode*.

> Be aware that different bios implementations may transfer control to 0x7c00
> differently as real mode uses segmented memory that could be for example
> `07c0:0000` or `0000:7c000`.

## Tips: real mode

The 16-bit real mode uses segmented memory where memory locations are often
denoted as `segment:offset` (in some specs also SegOff or logical address).

The logical address is turned into a linear address in real mode as follows.
```
(segment << 4) + offset
```

A segment resides in one of the segment selector register `ds, es, ss, fs, gs, cs`.

Note that this is completely different to how segmentation works in protected
mode, where segment selectors references an entry in the GDT.

## Tips: qemu

Some projects start qemu with graphical display and some without. The following
give some useful key maps when interacting with qemu.

```sh
# graphical: release mouse & keyboard grabbing from qemu ui
C-M-g

# terminal: terminate qemu
C-a x
```
