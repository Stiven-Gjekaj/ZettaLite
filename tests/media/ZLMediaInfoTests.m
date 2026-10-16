#import "ZLTest.h"
#import "ZLMediaInfo.h"
#import "ZLMediaTestSupport.h"

static ZLMediaInfo *InfoFor(ZLTestServer *server, NSString *name) {
    ZLInput *input = [ZLInput openURL:ZLFixtureURL(server, name) headers:nil error:NULL];
    return input ? [ZLMediaInfo infoForInput:input languages:nil] : nil;
}

ZL_TEST(test_info_sends_h264_to_the_system_player) {
    ZLTestServer *server = ZLFixtureServer();
    ZLMediaInfo *info = InfoFor(server, @"h264-aac.mp4");
    ZL_EQUAL_INT(info.route, ZLRouteSystem);
    ZL_EXPECT(info.audioPassThrough);
    ZL_EXPECT(fabs(info.duration - 24) < 0.1);
    info = InfoFor(server, @"h264-ac3.mkv");
    ZL_EQUAL_INT(info.route, ZLRouteSystem);
    ZL_EXPECT(!info.audioPassThrough);
    ZL_EQUAL(info.audio.codec, @"ac3");
    [server stop];
}

ZL_TEST(test_info_sends_hevc_and_vp9_to_the_software_player) {
    ZLTestServer *server = ZLFixtureServer();
    ZLMediaInfo *info = InfoFor(server, @"hevc-aac.mkv");
    ZL_EQUAL_INT(info.route, ZLRouteSoftware);
    ZL_EQUAL(info.video.codec, @"hevc");
    ZL_EXPECT(info.reason.length > 0);
    ZL_EQUAL_INT(InfoFor(server, @"vp9-opus.webm").route, ZLRouteSoftware);
    [server stop];
}

ZL_TEST(test_info_plays_audio_only_media_in_the_system_player) {
    ZLTestServer *server = ZLFixtureServer();
    ZLMediaInfo *info = InfoFor(server, @"audio.flac");
    ZL_EQUAL_INT(info.route, ZLRouteSystem);
    ZL_EXPECT(info.video == nil);
    ZL_EXPECT(!info.audioPassThrough);
    [server stop];
}
