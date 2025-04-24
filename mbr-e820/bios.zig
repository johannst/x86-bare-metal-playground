/// BIOS starts with video mode 0h.
///   * 80x25 text mode
///   * 16 colors (4bit)
/// http://www.ctyme.com/intr/rb-0069.htm
pub const COLS = 80;
pub const ROWS = 25;

/// BIOS CALL - video teletype output.
/// http://www.ctyme.com/intr/rb-0106.htm
pub fn putc(c: u8) void {
    // ah=0eh (call nr)
    // al=c   (ascii char to write)
    const ax = (@as(u16, 0xe) << 8) | c;

    _ = asm volatile (
        \\int $0x10
        : // No outputs.
        : [a] "{ax}" (ax), // BIOS call number + char to write.
        : "cc"
    );

    // On linefeed also write a carriage return to move to column 0.
    if (c == '\n') {
        putc('\r');
    }
}

const E820 = extern struct {
    base: u64 = 0,
    size: u64 = 0,
    kind: u32 = 0,
    attr: u32 = 1, // ACPI 3.0 compat
};

/// BIOS CALL - get system memory map
/// http://www.ctyme.com/intr/rb-1741.htm
/// https://wiki.osdev.org/Detecting_Memory_(x86)#BIOS_Function:_INT_0x15,_EAX_=_0xE820
pub fn e820(next_ebx: u32) ?struct { e820: E820, ebx: u32 } {
    var res = E820{};

    // Setup call number.
    var eax: u32 = 0xe820;
    // Setup size of entry, bios call will return actual bytes written.
    var ecx: u32 = @sizeOf(@TypeOf(res));
    // Setup continuation code, next one will be returned from the bios call.
    var ebx: u32 = next_ebx;

    const carry = asm volatile (
        \\int $0x15
        \\setc %[c]
        : // Outputs.
          [n] "+{eax}" (eax),
          [l] "+{ecx}" (ecx),
          [o] "+{ebx}" (ebx),
          [c] "={dl}" (-> u8), // Returns carry bit, recycle dl from dx.
        : // Inputs.
          [p] "{edi}" (&res), // Pointer to E820 entry.
          [m] "{edx}" (0x534D4150), // Magic number (b"SMAP").
        : // Clobbers.
          "cc"
    );

    // Call failed if carry is set.
    if (carry == 1) {
        return null;
    }
    // Call failed if magic number is not returned in eax.
    if (eax != 0x534D4150) {
        return null;
    }
    // Call failed if partial entry is written.
    if (ecx < 20) {
        return null;
    }

    return .{ .e820 = res, .ebx = ebx };
}
