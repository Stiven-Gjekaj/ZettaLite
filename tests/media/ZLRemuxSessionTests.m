#import "ZLTest.h"
#import "ZLMediaTestSupport.h"
#import "ZLRemuxSession.h"

// Joins the segments into one TS file and opens it, as the player does.
static ZLInput *JoinSegments(ZLRemuxSession *session, NSUInteger count) {
    NSMutableData *all = [NSMutableData data];
    for (NSUInteger i = 0; i < count; i++) {
        NSError *error = nil;
        NSData *segment = [session segmentAtIndex:i error:&error];
        if (!segment.length) {
            NSLog(@"segment %lu: %@", (unsigned long)i, error);
            return nil;
        }
        // Each segment starts with a TS sync byte.
        if (((const uint8_t *)segment.bytes)[0] != 0x47) return nil;
        [all appendData:segment];
    }
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"joined.ts"];
    [all writeToFile:path atomically:YES];
    return [ZLInput openURL:[NSURL fileURLWithPath:path] headers:nil error:NULL];
}

typedef struct {
    int videoFrames;
    int audioPackets;
    double audioGap;  // The largest gap or overlap between two audio packets, in seconds.
    enum AVCodecID videoCodec;
    enum AVCodecID audioCodec;
} Summary;

static Summary Summarize(ZLInput *input) {
    Summary summary = {0, 0, 0, AV_CODEC_ID_NONE, AV_CODEC_ID_NONE};
    AVFormatContext *context = input.context;
    int videoIndex = av_find_best_stream(context, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
    int audioIndex = av_find_best_stream(context, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
    if (videoIndex >= 0) summary.videoCodec = context->streams[videoIndex]->codecpar->codec_id;
    if (audioIndex >= 0) summary.audioCodec = context->streams[audioIndex]->codecpar->codec_id;
    AVPacket *packet = av_packet_alloc();
    int64_t expected = AV_NOPTS_VALUE;
    while (av_read_frame(context, packet) >= 0) {
        if (packet->stream_index == videoIndex) summary.videoFrames++;
        if (packet->stream_index == audioIndex) {
            summary.audioPackets++;
            if (expected != AV_NOPTS_VALUE) {
                double gap = fabs((double)(packet->pts - expected) * av_q2d(context->streams[audioIndex]->time_base));
                summary.audioGap = MAX(summary.audioGap, gap);
            }
            expected = packet->pts + packet->duration;
        }
        av_packet_unref(packet);
    }
    av_packet_free(&packet);
    return summary;
}

static ZLRemuxSession *Session(ZLTestServer *server, NSString *name) {
    ZLInput *input = [ZLInput openURL:ZLFixtureURL(server, name) headers:nil error:NULL];
    if (!input) return nil;
    ZLMediaInfo *info = [ZLMediaInfo infoForInput:input languages:nil];
    ZLRemuxSession *session = [[ZLRemuxSession alloc] initWithInput:input info:info audioIndex:-1];
    return [session prepare:NULL] ? session : nil;
}

ZL_TEST(test_remux_cuts_vod_files_at_keyframes_with_all_frames) {
    ZLTestServer *server = ZLFixtureServer();
    for (NSString *name in @[ @"h264-aac.mp4", @"h264-ac3.mkv", @"h264-opus.mkv", @"dash/manifest.mpd" ]) {
        ZLRemuxSession *session = Session(server, name);
        ZL_EXPECT(session != nil);
        if (!session) continue;
        ZL_EXPECT(!session.live);
        // 24 seconds in segments of about 6 seconds.
        ZL_EQUAL_INT(session.segmentCount, 4);
        double total = 0;
        for (NSUInteger i = 0; i < session.segmentCount; i++) total += [session durationOfSegment:i];
        ZL_EXPECT(fabs(total - 24) < 0.2);
        ZLInput *joined = JoinSegments(session, session.segmentCount);
        ZL_EXPECT(joined != nil);
        if (!joined) continue;
        Summary summary = Summarize(joined);
        ZL_EQUAL_INT(summary.videoCodec, AV_CODEC_ID_H264);
        ZL_EQUAL_INT(summary.audioCodec, AV_CODEC_ID_AAC);
        // 24 seconds at 25 frames per second, with no frame lost or doubled.
        ZL_EQUAL_INT(summary.videoFrames, 600);
        // 24 seconds of AAC at 48 kHz is 1125 frames of 1024 samples.
        ZL_EXPECT(abs(summary.audioPackets - 1125) <= 2);
        ZL_EXPECT(summary.audioGap < 0.005);
        if (summary.audioGap >= 0.005 || abs(summary.audioPackets - 1125) > 2) {
            NSLog(@"%@: %d audio packets, gap %f", name, summary.audioPackets, summary.audioGap);
        }
        [session close];
    }
    [server stop];
}

ZL_TEST(test_remux_gives_a_segment_again_after_a_seek) {
    ZLTestServer *server = ZLFixtureServer();
    ZLRemuxSession *session = Session(server, @"h264-ac3.mkv");
    NSData *third = [session segmentAtIndex:2 error:NULL];
    [session segmentAtIndex:0 error:NULL];
    NSData *again = [session segmentAtIndex:2 error:NULL];
    ZL_EXPECT(third.length > 0);
    ZL_EQUAL_INT(again.length, third.length);
    [session close];
    [server stop];
}

ZL_TEST(test_remux_plays_a_stream_that_cannot_seek_as_live) {
    ZLTestServer *server = ZLFixtureServer();
    server.acceptsRanges = NO;
    ZLRemuxSession *session = Session(server, @"h264-aac.ts");
    ZL_EXPECT(session.live);
    NSString *playlist = [[NSString alloc] initWithData:[session playlist] encoding:NSUTF8StringEncoding];
    ZL_EXPECT([playlist rangeOfString:@"#EXT-X-MEDIA-SEQUENCE:0"].location != NSNotFound);
    ZL_EXPECT([playlist rangeOfString:@"2.ts"].location != NSNotFound);
    ZL_EXPECT([session segmentAtIndex:0 error:NULL].length > 0);
    [session close];
    [server stop];
}
