#import "ZLDecodeLimits.h"

// The decode, the display, and the sound must fit. The decode gets at most
// 1 / 1.2 of the time.
static const double ZLDecodeMargin = 1.2;

double ZLSoftwareDecodeCapacity(NSString *codec, int bitDepth) {
    BOOL deep = bitDepth > 8;
    // Pixels per second: the measured speed times the pixel rate of the test
    // file. 10-bit VP9, 10-bit AV1, VP8, and Theora are estimates. The
    // others are measured.
    if ([codec isEqualToString:@"h264"]) return deep ? 17.7e6 : 36.5e6;
    if ([codec isEqualToString:@"hevc"]) return deep ? 10.6e6 : 15.5e6;
    if ([codec isEqualToString:@"vp9"]) return deep ? 15.0e6 : 29.0e6;
    if ([codec isEqualToString:@"av1"] || [codec isEqualToString:@"libdav1d"]) return deep ? 14.0e6 : 24.0e6;
    if ([codec isEqualToString:@"mpeg2video"] || [codec isEqualToString:@"mpeg1video"]) return 107e6;
    if ([codec isEqualToString:@"mpeg4"] || [codec isEqualToString:@"msmpeg4v3"]) return 116e6;
    if ([codec isEqualToString:@"vp8"] || [codec isEqualToString:@"theora"]) return 40e6;
    return 0;
}

BOOL ZLSoftwareDecodeFits(NSString *codec, int bitDepth, int width, int height, double fps) {
    double capacity = ZLSoftwareDecodeCapacity(codec, bitDepth);
    if (capacity <= 0 || width <= 0 || height <= 0) return NO;
    double rate = (double)width * height * (fps > 0 ? fps : 30);
    return rate * ZLDecodeMargin <= capacity;
}
