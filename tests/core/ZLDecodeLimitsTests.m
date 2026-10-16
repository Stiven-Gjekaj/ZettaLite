#import "ZLTest.h"
#import "ZLDecodeLimits.h"

ZL_TEST(test_limits_follow_the_measured_speeds) {
    // HEVC: 480p plays, 720p is too heavy.
    ZL_EXPECT(ZLSoftwareDecodeFits(@"hevc", 8, 854, 480, 24));
    ZL_EXPECT(!ZLSoftwareDecodeFits(@"hevc", 8, 1280, 720, 24));
    // 10-bit HEVC at 480p and 30 frames per second is too heavy. 360p plays.
    ZL_EXPECT(!ZLSoftwareDecodeFits(@"hevc", 10, 854, 480, 30));
    ZL_EXPECT(ZLSoftwareDecodeFits(@"hevc", 10, 640, 360, 30));
    // VP9 plays 720p at 24 frames per second, but not at 30.
    ZL_EXPECT(ZLSoftwareDecodeFits(@"vp9", 8, 1280, 720, 24));
    ZL_EXPECT(!ZLSoftwareDecodeFits(@"vp9", 8, 1280, 720, 30));
    // H.264 in software plays 720p, but not 1080p.
    ZL_EXPECT(ZLSoftwareDecodeFits(@"h264", 8, 1280, 720, 30));
    ZL_EXPECT(!ZLSoftwareDecodeFits(@"h264", 8, 1920, 1080, 24));
    // MPEG-2 plays 1080i.
    ZL_EXPECT(ZLSoftwareDecodeFits(@"mpeg2video", 8, 1920, 1080, 30));
}

ZL_TEST(test_limits_refuse_an_unknown_codec_or_size) {
    ZL_EXPECT(!ZLSoftwareDecodeFits(@"prores", 10, 640, 360, 24));
    ZL_EXPECT(!ZLSoftwareDecodeFits(@"hevc", 8, 0, 0, 24));
    ZL_EQUAL_INT((long long)ZLSoftwareDecodeCapacity(@"none", 8), 0);
}
