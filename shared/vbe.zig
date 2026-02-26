// SPDX-License-Identifier: MIT
//
// Copyright (c) 2026, Johannes Stoelp <dev@memzero.de>

const std = @import("std");
const SegOff = @import("segoff.zig").SegOff;

pub const VbeInfoBlock = extern struct {
    /// VBE signature, used as inout.
    signature: [4]u8 align(1),
    /// VBE version (0x200 for VBE2, 0x300 for VBE3).
    version: u16 align(1),
    /// Far pointer to OEM string.
    oem: SegOff align(1),
    /// Capabilities of the graphic controller.
    capabilities: [4]u8 align(1),
    /// Far pointer to the video mode list. This is an array of u16 elements
    /// with the supported modes. The terminal node 0xffff marks the end.
    video_mode: SegOff align(1),
    /// Number of 64k vram blocks (VBE2+).
    vram_blocks: u16 align(1),
    /// VBE oem software revision.
    oem_sw_rev: u16 align(1),
    /// Far pointer to vendor name string.
    oem_vendor_name: SegOff align(1),
    /// Far pointer to product name string.
    oem_product_name: SegOff align(1),
    /// Far pointer to product revision string.
    oem_product_rev: SegOff align(1),
    /// Scratch area for VBE implementation.
    reserved: [222]u8 align(1),
    /// Data for OEM strings.
    oem_data: [256]u8 align(1),

    pub fn init() VbeInfoBlock {
        var info = std.mem.zeroes(VbeInfoBlock);
        @memcpy(&info.signature, "VBE2");
        return info;
    }

    pub fn validSignature(self: *const VbeInfoBlock) bool {
        return std.mem.eql(u8, &self.signature, "VESA");
    }

    pub fn modes(self: *const VbeInfoBlock) []u16 {
        const modeptr = @as([*:0xffff]u16, @ptrFromInt(self.video_mode.linear()));

        var cnt: usize = 0;
        while (modeptr[cnt] != 0xffff) {
            cnt += 1;
        }

        return modeptr[0..cnt];
    }
};

pub const ModeInfoBlock = extern struct {
    /// Mode attributes.
    mode_attrs: u16 align(1),

    /// Window A attributes.
    win_a_attrs: u8 align(1),
    /// Window B attributes.
    win_b_attrs: u8 align(1),
    /// Window granularity.
    win_granularity: u16 align(1),
    /// Window size.
    win_size: u16 align(1),
    /// Window A start segment.
    win_a_segment: u16 align(1),
    /// Window B start segment.
    win_b_segment: u16 align(1),
    /// Far pointer to (real mode) window function.
    win_fun_ptr: SegOff align(1),

    /// Bytes per scanline (one horizontal line).
    bytes_per_scan_line: u16 align(1),
    /// Horizontal resolution in pixels (graphic) or chars (text).
    x_res: u16 align(1),
    /// Vertical resolution in pixels (graphic) or chars (text).
    y_res: u16 align(1),
    /// Character cell width in pixel.
    x_char_size: u8 align(1),
    /// Character cell height in pixel.
    y_char_size: u8 align(1),
    /// Number of memory planes.
    num_planes: u8 align(1),
    /// Bits per pixel.
    bits_per_pixel: u8 align(1),
    /// Number of banks.
    num_banks: u8 align(1),
    /// Memory mode.
    memory_model: u8 align(1),
    /// Bank size in KB.
    bank_size: u8 align(1),
    /// Numbe of images.
    num_img_pages: u8 align(1),
    // Reserved.
    reserved: u8 align(1),

    // Direct color fields.
    /// Red mask size in bits, effectively number of red bits.
    red_mask_size: u8 align(1),
    /// Bit offset for red bits.
    red_field_pos: u8 align(1),
    /// Green mask size in bits, effectively number of green bits.
    green_mask_size: u8 align(1),
    /// Bit offset for green bits.
    green_field_pos: u8 align(1),
    /// Blue mask size in bits, effectively number of blue bits.
    blue_mask_size: u8 align(1),
    /// Bit offset for blue bits.
    blue_field_pos: u8 align(1),
    // Reserved.
    rsvd_mask_size: u8 align(1),
    rsvd_field_pos: u8 align(1),
    /// Direct color mode attributes.
    direct_color_mode_info: u8 align(1),

    /// Physical address of linear frame buffer (for modes with linear fb).
    phys_base: u32 align(1),

    /// Squashed fields not used here.
    _compated: [22]u8 align(1),
    // Reserved.
    reserved3: [190]u8 align(1),

    pub fn isSupported(self: *ModeInfoBlock) bool {
        const MODE_SUPPORTED = (1 << 0);
        return (self.mode_attrs & MODE_SUPPORTED) == MODE_SUPPORTED;
    }

    pub fn isGraphic(self: *ModeInfoBlock) bool {
        const MODE_TYPE = (1 << 4);
        return (self.mode_attrs & MODE_TYPE) == MODE_TYPE;
    }

    pub fn isText(self: *ModeInfoBlock) bool {
        return !self.isGraphic();
    }

    pub fn hasLinearFramebuffer(self: *ModeInfoBlock) bool {
        const MODE_LFB = (1 << 7);
        return (self.mode_attrs & MODE_LFB) == MODE_LFB;
    }

    pub fn isDirectColor(self: *ModeInfoBlock) bool {
        const MM_PACKED_PIXEL = 0x04;
        const MM_DIRECT_COLOR = 0x06;
        return self.memory_model == MM_PACKED_PIXEL or self.memory_model == MM_DIRECT_COLOR;
    }
};

comptime {
    // For VBE2.0 info block is 512 bytes.
    std.debug.assert(@sizeOf(VbeInfoBlock) == 512);
    // For VBE2.0 mode info block is 256 bytes.
    std.debug.assert(@sizeOf(ModeInfoBlock) == 256);
}

pub fn checkVbeRet(ax: u16) !void {
    const al: u8 = @truncate(ax);
    const ah: u8 = @truncate(ax >> 8);

    if (al != 0x4f)
        return error.VbeFnNotSupported;

    return switch (ah) {
        0x00 => {}, // success
        0x01 => error.VbeFnCallFailed,
        0x02 => error.VbeFnNotSupportedInHwConfig,
        0x03 => error.VbeFnCallInvalidInVideoConfig,
        else => error.VbeUnknownError,
    };
}
