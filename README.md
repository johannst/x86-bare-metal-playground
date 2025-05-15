# x86 bare metal playground

This repository mainly serves as playground for bare metal x86 experiments,
testing different assembly flavors and learning bare metal zig.

One can just execute `make run` in each sub-directory to build and run the given
project.

For convenience, the [`flake.nix`](flake.nix) provides a development environment.
One can execute `nix develop --command make -C multiboot run` to run the
[multiboot](multiboot) project for example. Alternatively one can just run `nix
develop` to drop into an interactive shell.

## Tips

Some projects start qemu with graphical display and some without. The following give some
useful key maps when interacting with qemu.

```sh
# graphical: release mouse & keyboard grabbing from qemu ui
C-M-g

# terminal: terminate qemu
C-a x
```
