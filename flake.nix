# SPDX-License-Identifier: MIT
#
# Copyright (c) 2026, Johannes Stoelp <dev@memzero.de>
{
  description = "x86 bare metal development environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }: let
    system = "x86_64-linux";
    pkgs   = import nixpkgs { inherit system; };
  in {
    devShells.${system}.default = pkgs.mkShell {
      buildInputs = [
        pkgs.zig
        pkgs.zls
        pkgs.qemu
        pkgs.xxd
        pkgs.rsync
        pkgs.grub2
        pkgs.libisoburn
      ];
      shellHook = ''
        # https://github.com/NixOS/nixpkgs/issues/270415
        unset ZIG_GLOBAL_CACHE_DIR
      '';
    };
  };
}
