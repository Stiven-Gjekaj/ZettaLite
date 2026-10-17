// Gives one input to the system player as HLS on 127.0.0.1.
//
// A file that can seek becomes a VOD playlist. Each segment starts at a
// video keyframe. FFmpeg copies the H.264 video into MPEG-TS, and it copies
// AAC or MP3 audio, or it changes other audio into AAC.
//
// An input that cannot seek, for example a live channel, becomes a live
// playlist. One reader cuts the input into segments as they come, and the
// playlist holds the newest ones.

#import <Foundation/Foundation.h>
#import "ZLHLSServer.h"
#import "ZLInput.h"
#import "ZLMediaInfo.h"
#import "ZLEmbeddedSubtitles.h"

// The target length of a segment in seconds.
extern const double ZLSegmentSeconds;

@interface ZLRemuxSession : NSObject <ZLHLSSource>

@property (nonatomic, readonly) ZLMediaInfo *info;
@property (nonatomic, readonly) BOOL live;
@property (nonatomic, readonly) NSUInteger segmentCount;  // 0 for live.
// The cues of the text subtitles that the reads found. Set after prepare.
@property (nonatomic, readonly) ZLEmbeddedSubtitles *subtitles;

// The session owns the input from now on. audioIndex selects an audio
// stream, or -1 for the choice of info.
- (instancetype)initWithInput:(ZLInput *)input info:(ZLMediaInfo *)info audioIndex:(int)audioIndex;

// Reads the index of the input. It blocks.
- (BOOL)prepare:(NSError **)error;

// The start and the length of a VOD segment, in seconds.
- (double)startOfSegment:(NSUInteger)index;
- (double)durationOfSegment:(NSUInteger)index;

// Stops the reads and closes the input.
- (void)close;

@end
