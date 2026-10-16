#import "ZLTest.h"
#import "ZLInput.h"
#import "ZLTrust.h"
#import "ZLMediaTestSupport.h"

static enum AVCodecID CodecOf(ZLInput *input, enum AVMediaType type) {
    for (unsigned i = 0; i < input.context->nb_streams; i++) {
        AVCodecParameters *codec = input.context->streams[i]->codecpar;
        if (codec->codec_type == type) return codec->codec_id;
    }
    return AV_CODEC_ID_NONE;
}

ZL_TEST(test_input_opens_media_over_http) {
    ZLTestServer *server = ZLFixtureServer();
    NSDictionary *expected = @{
        @"h264-aac.mp4": @[ @(AV_CODEC_ID_H264), @(AV_CODEC_ID_AAC) ],
        @"h264-ac3.mkv": @[ @(AV_CODEC_ID_H264), @(AV_CODEC_ID_AC3) ],
        @"h264-aac.ts": @[ @(AV_CODEC_ID_H264), @(AV_CODEC_ID_AAC) ],
        @"hevc-aac.mkv": @[ @(AV_CODEC_ID_HEVC), @(AV_CODEC_ID_AAC) ],
        @"vp9-opus.webm": @[ @(AV_CODEC_ID_VP9), @(AV_CODEC_ID_OPUS) ],
        @"dash/manifest.mpd": @[ @(AV_CODEC_ID_H264), @(AV_CODEC_ID_AAC) ],
    };
    for (NSString *name in expected) {
        NSError *error = nil;
        ZLInput *input = [ZLInput openURL:ZLFixtureURL(server, name) headers:@{ @"User-Agent": @"ZLTest" } error:&error];
        ZL_EXPECT(input != nil);
        if (!input) {
            NSLog(@"%@: %@", name, error);
            continue;
        }
        ZL_EQUAL_INT(CodecOf(input, AVMEDIA_TYPE_VIDEO), [expected[name][0] intValue]);
        ZL_EQUAL_INT(CodecOf(input, AVMEDIA_TYPE_AUDIO), [expected[name][1] intValue]);
        ZL_EQUAL(server.lastHeaders[@"user-agent"], @"ZLTest");
        [input close];
    }
    [server stop];
}

ZL_TEST(test_input_reports_a_missing_file) {
    ZLTestServer *server = ZLFixtureServer();
    NSError *error = nil;
    ZL_EXPECT(![ZLInput openURL:ZLFixtureURL(server, @"none.mkv") headers:nil error:&error]);
    ZL_EQUAL_INT(error.code, ZLErrorHTTPStatus);
    [server stop];
}
