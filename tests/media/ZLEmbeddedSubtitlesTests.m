#import "ZLTest.h"
#import "ZLEmbeddedSubtitles.h"
#import "ZLInput.h"
#import "ZLMediaTestSupport.h"

static ZLCueList *ReadCues(ZLTestServer *server, NSString *name) {
    ZLInput *input = [ZLInput openURL:ZLFixtureURL(server, name) headers:nil error:NULL];
    if (!input) return nil;
    AVFormatContext *context = input.context;
    double origin = context->start_time != AV_NOPTS_VALUE ? context->start_time / (double)AV_TIME_BASE : 0;
    // Read only the subtitles, as a player that reads all packets does.
    for (unsigned i = 0; i < context->nb_streams; i++) context->streams[i]->discard = AVDISCARD_ALL;
    ZLEmbeddedSubtitles *subtitles = [[ZLEmbeddedSubtitles alloc] initWithContext:context origin:origin];
    if (subtitles.indexes.count != 1) return nil;
    AVPacket *packet = av_packet_alloc();
    while (av_read_frame(context, packet) >= 0) {
        [subtitles takePacket:packet];
        av_packet_unref(packet);
    }
    av_packet_free(&packet);
    ZLCueList *cues = [subtitles cuesOfStream:[subtitles.indexes[0] intValue]];
    [input close];
    return cues;
}

ZL_TEST(test_embedded_subtitles_read_srt_ass_and_mov_text) {
    ZLTestServer *server = ZLFixtureServer();
    for (NSString *name in @[ @"subs-srt.mkv", @"subs-ass.mkv", @"subs-text.mp4" ]) {
        ZLCueList *cues = ReadCues(server, name);
        ZL_EQUAL_INT([cues count], 2);
        ZL_EQUAL([cues textAt:2], @"First line");
        ZL_EXPECT([cues textAt:5] == nil);
        ZL_EQUAL([cues textAt:12.3], @"Second line\nwith two rows");
    }
    // A file with no subtitles has no text streams.
    ZLInput *input = [ZLInput openURL:ZLFixtureURL(server, @"h264-aac.mp4") headers:nil error:NULL];
    ZL_EQUAL_INT([[ZLEmbeddedSubtitles alloc] initWithContext:input.context origin:0].indexes.count, 0);
    [input close];
    [server stop];
}
