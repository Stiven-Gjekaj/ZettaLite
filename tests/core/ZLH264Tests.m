#import "ZLTest.h"
#import "ZLH264.h"

static NSData *Hex(NSString *text) {
    NSMutableData *data = [NSMutableData data];
    for (NSUInteger i = 0; i + 1 < text.length; i += 2) {
        unsigned value = 0;
        [[NSScanner scannerWithString:[text substringWithRange:NSMakeRange(i, 2)]] scanHexInt:&value];
        uint8_t byte = (uint8_t)value;
        [data appendBytes:&byte length:1];
    }
    return data;
}

// The avcC of a 720p file with 16 reference frames, from x264 with the placebo preset.
static NSString *const ZLManyRefs = @"01640032ffe1001b67640032ac7284405005bb0110000003001000000303c0f183184601000768e843874b22c0";

ZL_TEST(test_h264_reads_the_reference_frames_and_the_size) {
    NSData *data = Hex(ZLManyRefs);
    ZLH264Info info;
    ZL_EXPECT(ZLParseH264Extradata(data.bytes, data.length, &info));
    ZL_EQUAL_INT(info.profile, 100);
    ZL_EQUAL_INT(info.level, 50);
    ZL_EQUAL_INT(info.refs, 16);
    ZL_EQUAL_INT(info.width, 1280);
    ZL_EQUAL_INT(info.height, 720);
    ZL_EQUAL_INT(info.bitDepth, 8);
    // 720p permits 9 reference frames in the hardware decoder.
    ZL_EQUAL_INT(ZLH264HardwareRefLimit(1280, 720), 9);
    ZL_EQUAL_INT(ZLH264HardwareRefLimit(1920, 1080), 4);
}

ZL_TEST(test_h264_reads_an_annex_b_sps) {
    NSData *avcc = Hex(ZLManyRefs);
    NSMutableData *annexB = [NSMutableData dataWithBytes:"\x00\x00\x00\x01" length:4];
    [annexB appendData:[avcc subdataWithRange:NSMakeRange(8, 27)]];
    [annexB appendBytes:"\x00\x00\x00\x01\x68\xe8" length:6];
    ZLH264Info info;
    ZL_EXPECT(ZLParseH264Extradata(annexB.bytes, annexB.length, &info));
    ZL_EQUAL_INT(info.refs, 16);
}

ZL_TEST(test_h264_refuses_short_data) {
    ZLH264Info info;
    ZL_EXPECT(!ZLParseH264Extradata((const uint8_t *)"\x01\x64", 2, &info));
    ZL_EXPECT(!ZLParseH264Extradata(NULL, 0, &info));
}
