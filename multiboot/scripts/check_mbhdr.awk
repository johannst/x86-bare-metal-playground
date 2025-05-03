# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

BEGIN {
    # > xxd -d -e -c 4 IMG
    #   00004096: 1badb002  ....
    #
    # Split at colon to easily extract file offset.
    FS = ":"

    # An OS image must contain an additional header called Multiboot header,
    # besides the headers of the format used by the OS image. The Multiboot
    # header must be contained completely within the first 8192 bytes of the OS
    # image, and must be longword (32-bit) aligned. In general, it should come
    # as early as possible, and may be embedded in the beginning of the text
    # segment after the real executable header.
    #
    # https://www.gnu.org/software/grub/manual/multiboot/multiboot.html
    MBHDR_LIMIT = 8192;
    MBHDR_ALIGN = 4;

    MBHDR_SIZE  = 3 * 4;
}

/1badb002/ {
    print $0" off="$1

    if ($1 > MBHDR_LIMIT - MBHDR_SIZE) {
        print "FAIL: multiboot header must be in the first "$MBHDR_SIZE" bytes of the image!"
        exit 1
    }

    if ($1 % MBHDR_ALIGN != 0) {
        print "FAIL: multiboot header must be 32bit aligned!"
        exit 1
    }

    exit 0
}
