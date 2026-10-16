#import "ZLH264.h"

// Reads bits of an RBSP, with the emulation prevention bytes removed.
typedef struct {
    const uint8_t *bytes;
    size_t size;
    size_t bit;
} ZLBits;

static unsigned ZLReadBit(ZLBits *bits) {
    if (bits->bit >= bits->size * 8) {
        bits->bit++;
        return 0;
    }
    unsigned value = (bits->bytes[bits->bit / 8] >> (7 - bits->bit % 8)) & 1;
    bits->bit++;
    return value;
}

static unsigned ZLReadBitsN(ZLBits *bits, int count) {
    unsigned value = 0;
    for (int i = 0; i < count; i++) value = (value << 1) | ZLReadBit(bits);
    return value;
}

static unsigned ZLReadUE(ZLBits *bits) {
    int zeros = 0;
    while (ZLReadBit(bits) == 0 && zeros < 32) zeros++;
    if (zeros >= 32) return 0;
    return ((1u << zeros) - 1) + ZLReadBitsN(bits, zeros);
}

static int ZLReadSE(ZLBits *bits) {
    unsigned value = ZLReadUE(bits);
    return (value & 1) ? (int)((value + 1) / 2) : -(int)(value / 2);
}

static void ZLSkipScalingList(ZLBits *bits, int size) {
    int last = 8, next = 8;
    for (int i = 0; i < size; i++) {
        if (next != 0) next = (last + ZLReadSE(bits) + 256) % 256;
        last = next == 0 ? last : next;
    }
}

static BOOL ZLParseSPS(const uint8_t *nal, size_t size, ZLH264Info *info) {
    if (size < 4 || (nal[0] & 0x1f) != 7) return NO;
    // Remove the emulation prevention bytes (00 00 03).
    NSMutableData *rbsp = [NSMutableData dataWithCapacity:size];
    int zeros = 0;
    for (size_t i = 1; i < size; i++) {
        if (zeros >= 2 && nal[i] == 3) {
            zeros = 0;
            continue;
        }
        zeros = nal[i] == 0 ? zeros + 1 : 0;
        [rbsp appendBytes:&nal[i] length:1];
    }
    ZLBits bits = {rbsp.bytes, rbsp.length, 0};
    memset(info, 0, sizeof(*info));
    info->profile = (int)ZLReadBitsN(&bits, 8);
    ZLReadBitsN(&bits, 8);  // The constraint flags.
    info->level = (int)ZLReadBitsN(&bits, 8);
    ZLReadUE(&bits);  // seq_parameter_set_id
    info->bitDepth = 8;
    int profile = info->profile;
    if (profile == 100 || profile == 110 || profile == 122 || profile == 244 || profile == 44 || profile == 83 ||
        profile == 86 || profile == 118 || profile == 128 || profile == 138 || profile == 139 || profile == 134) {
        unsigned chroma = ZLReadUE(&bits);
        if (chroma == 3) ZLReadBit(&bits);  // separate_colour_plane_flag
        info->bitDepth = 8 + (int)ZLReadUE(&bits);
        ZLReadUE(&bits);  // bit_depth_chroma_minus8
        ZLReadBit(&bits);  // qpprime_y_zero_transform_bypass_flag
        if (ZLReadBit(&bits)) {
            int lists = chroma == 3 ? 12 : 8;
            for (int i = 0; i < lists; i++) {
                if (ZLReadBit(&bits)) ZLSkipScalingList(&bits, i < 6 ? 16 : 64);
            }
        }
    }
    ZLReadUE(&bits);  // log2_max_frame_num_minus4
    unsigned orderType = ZLReadUE(&bits);
    if (orderType == 0) {
        ZLReadUE(&bits);
    } else if (orderType == 1) {
        ZLReadBit(&bits);
        ZLReadSE(&bits);
        ZLReadSE(&bits);
        unsigned cycle = ZLReadUE(&bits);
        for (unsigned i = 0; i < cycle && i < 256; i++) ZLReadSE(&bits);
    }
    info->refs = (int)ZLReadUE(&bits);
    ZLReadBit(&bits);  // gaps_in_frame_num_value_allowed_flag
    int widthMbs = (int)ZLReadUE(&bits) + 1;
    int heightUnits = (int)ZLReadUE(&bits) + 1;
    int frameMbsOnly = (int)ZLReadBit(&bits);
    info->width = widthMbs * 16;
    info->height = heightUnits * 16 * (frameMbsOnly ? 1 : 2);
    return bits.bit <= bits.size * 8;
}

BOOL ZLParseH264Extradata(const uint8_t *data, size_t size, ZLH264Info *info) {
    if (!data || size < 8) return NO;
    if (data[0] == 1) {
        // avcC: version, profile, compatibility, level, length size, SPS count.
        int count = data[5] & 0x1f;
        if (count < 1) return NO;
        size_t length = ((size_t)data[6] << 8) | data[7];
        if (8 + length > size) return NO;
        return ZLParseSPS(data + 8, length, info);
    }
    // Annex B: find each start code, and read the first SPS.
    for (size_t i = 0; i + 3 < size; i++) {
        if (data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 1) {
            size_t start = i + 3;
            size_t end = start;
            while (end + 2 < size && !(data[end] == 0 && data[end + 1] == 0 && (data[end + 2] == 1 || data[end + 2] == 0))) end++;
            if (end + 2 >= size) end = size;
            if ((data[start] & 0x1f) == 7) return ZLParseSPS(data + start, end - start, info);
            i = end - 1;
        }
    }
    return NO;
}

int ZLH264HardwareRefLimit(int width, int height) {
    int macroblocks = ((width + 15) / 16) * ((height + 15) / 16);
    if (macroblocks <= 0) return 16;
    return MIN(16, 32768 / macroblocks);
}
