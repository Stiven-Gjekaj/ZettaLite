#import "ZLTest.h"
#import "ZLMediaTestSupport.h"
#import "ZLPlayerEngine.h"

@interface ZLEngineWatcher : NSObject <ZLPlayerEngineDelegate>
@property (nonatomic) BOOL ended;
@end

@implementation ZLEngineWatcher
- (void)engineDidChangeState:(ZLPlayerEngine *)engine {
}
- (void)engineDidEnd:(ZLPlayerEngine *)engine {
    self.ended = YES;
}
- (void)engine:(ZLPlayerEngine *)engine didFail:(NSError *)error {
}
@end

// Runs the run loop for some seconds, and takes the frames as a display does.
static NSUInteger ShowFrames(ZLPlayerEngine *engine, NSTimeInterval seconds, ZLVideoFrame **last) {
    NSUInteger shown = 0;
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([until timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.0 / 60]];
        ZLVideoFrame *frame = [engine frameToShow];
        if (frame) {
            shown++;
            if (last) *last = frame;
        }
    }
    return shown;
}

static ZLPlayerEngine *Engine(ZLTestServer *server, NSString *name) {
    ZLInput *input = [ZLInput openURL:ZLFixtureURL(server, name) headers:nil error:NULL];
    if (!input) return nil;
    return [[ZLPlayerEngine alloc] initWithInput:input info:[ZLMediaInfo infoForInput:input languages:nil]];
}

ZL_TEST(test_engine_plays_hevc_with_sound_in_time) {
    ZLTestServer *server = ZLFixtureServer();
    ZLPlayerEngine *engine = Engine(server, @"hevc-aac.mkv");
    ZL_EXPECT([engine startAt:0 error:NULL]);
    ZLVideoFrame *last = nil;
    NSUInteger shown = ShowFrames(engine, 4, &last);
    double position = [engine position];
    // The clock runs at real time after a short start.
    ZL_EXPECT(position > 2.5 && position < 4.2);
    // 25 frames per second, with no more than a few late frames.
    ZL_EXPECT(shown >= (NSUInteger)((position - 0.5) * 25));
    ZL_EQUAL_INT(last.width, 320);
    ZL_EXPECT(fabs(last.time - position) < 0.2);
    if (!(position > 2.5 && position < 4.2) || shown < (NSUInteger)((position - 0.5) * 25)) {
        NSLog(@"position %.2f, shown %lu, dropped %lu", position, (unsigned long)shown, (unsigned long)engine.droppedFrames);
    }
    [engine close];
    [server stop];
}

ZL_TEST(test_engine_seeks_and_pauses) {
    ZLTestServer *server = ZLFixtureServer();
    ZLPlayerEngine *engine = Engine(server, @"vp9-opus.webm");
    ZL_EXPECT([engine startAt:10 error:NULL]);
    ZLVideoFrame *last = nil;
    ShowFrames(engine, 2, &last);
    ZL_EXPECT([engine position] >= 10 && [engine position] < 12.5);
    ZL_EXPECT(last.time >= 9.9);
    [engine seekTo:3];
    ShowFrames(engine, 1.5, &last);
    ZL_EXPECT([engine position] >= 3 && [engine position] < 5);
    [engine setPaused:YES];
    ShowFrames(engine, 0.3, NULL);
    double paused = [engine position];
    ShowFrames(engine, 1, NULL);
    ZL_EXPECT(fabs([engine position] - paused) < 0.05);
    [engine close];
    [server stop];
}

ZL_TEST(test_engine_ends_at_the_end) {
    ZLTestServer *server = ZLFixtureServer();
    ZLPlayerEngine *engine = Engine(server, @"hevc-aac.mkv");
    ZLEngineWatcher *watcher = [ZLEngineWatcher new];
    engine.delegate = watcher;
    ZL_EXPECT([engine startAt:21 error:NULL]);
    ShowFrames(engine, 5, NULL);
    ZL_EXPECT(watcher.ended);
    [engine close];
    [server stop];
}
