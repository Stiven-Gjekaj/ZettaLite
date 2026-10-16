// remux: run the remux of the app on the phone without the interface. It
// prints the time of each step and saves each segment as /tmp/seg<N>.ts.
// Usage: remux URL [SEGMENTS]

#import <Foundation/Foundation.h>
#import "ZLInput.h"
#import "ZLMediaInfo.h"
#import "ZLRemuxSession.h"

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: remux URL [SEGMENTS]\n");
            return 2;
        }
        av_log_set_level(AV_LOG_WARNING);
        NSURL *url = [NSURL URLWithString:@(argv[1])];
        NSDate *start = [NSDate date];
        NSError *error = nil;
        ZLInput *input = [ZLInput openURL:url headers:nil error:&error];
        if (!input) {
            printf("open failed: %s\n", error.localizedDescription.UTF8String);
            return 1;
        }
        printf("open: %.2f s, seekable %d\n", -[start timeIntervalSinceNow], input.seekable);
        ZLMediaInfo *info = [ZLMediaInfo infoForInput:input languages:nil];
        printf("route %ld, video %s %dx%d, audio %s, pass %d, duration %.2f\n", (long)info.route,
               info.video.codec.UTF8String, info.video.width, info.video.height, info.audio.codec.UTF8String,
               info.audioPassThrough, info.duration);
        ZLRemuxSession *session = [[ZLRemuxSession alloc] initWithInput:input info:info audioIndex:-1];
        start = [NSDate date];
        if (![session prepare:&error]) {
            printf("prepare failed: %s\n", error.localizedDescription.UTF8String);
            return 1;
        }
        printf("prepare: %.2f s, live %d, %lu segments\n", -[start timeIntervalSinceNow], session.live,
               (unsigned long)session.segmentCount);
        printf("%s", [[NSString alloc] initWithData:[session playlist] encoding:NSUTF8StringEncoding].UTF8String);
        NSUInteger count = argc > 2 ? (NSUInteger)atoi(argv[2]) : MIN(session.segmentCount, 3u);
        for (NSUInteger i = 0; i < count; i++) {
            start = [NSDate date];
            NSData *segment = [session segmentAtIndex:i error:&error];
            printf("segment %lu: %lu bytes, %.2f s %s\n", (unsigned long)i, (unsigned long)segment.length,
                   -[start timeIntervalSinceNow], segment ? "" : error.localizedDescription.UTF8String);
            [segment writeToFile:[NSString stringWithFormat:@"/tmp/seg%lu.ts", (unsigned long)i] atomically:NO];
        }
        [session close];
    }
    return 0;
}
