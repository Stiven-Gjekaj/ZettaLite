// The engine of the own player. It plays the video codecs that the hardware
// of the A5 chip cannot decode: HEVC, VP9, AV1, MPEG-2, MPEG-4 ASP, 10-bit
// H.264, and H.264 with too many reference frames.
//
// One thread reads the packets. One thread decodes the video on 2 cores into
// a small queue of frames. One thread decodes the audio into a ring buffer,
// and an AudioQueue plays it. The audio is the clock. The display asks for
// the frame of the current time.

#import <Foundation/Foundation.h>
#import "ZLInput.h"
#import "ZLMediaInfo.h"
#import "ZLEmbeddedSubtitles.h"

// One decoded picture in 8-bit YUV 4:2:0, with each plane packed tight.
@interface ZLVideoFrame : NSObject
@property (nonatomic, readonly) int width;
@property (nonatomic, readonly) int height;
@property (nonatomic, readonly) double time;  // Seconds from the start of the media.
@property (nonatomic, readonly) NSData *luma;  // width x height
@property (nonatomic, readonly) NSData *blue;  // (width + 1) / 2 x (height + 1) / 2
@property (nonatomic, readonly) NSData *red;
@property (nonatomic, readonly) BOOL fullRange;
@property (nonatomic, readonly) BOOL hd;  // BT.709 colors. Otherwise BT.601.
@property (nonatomic, readonly) double aspect;  // The display width divided by the display height.
@end

@class ZLPlayerEngine;

@protocol ZLPlayerEngineDelegate <NSObject>
// These come on the main thread.
- (void)engineDidChangeState:(ZLPlayerEngine *)engine;
- (void)engineDidEnd:(ZLPlayerEngine *)engine;
- (void)engine:(ZLPlayerEngine *)engine didFail:(NSError *)error;
@end

@interface ZLPlayerEngine : NSObject

@property (nonatomic, weak) id<ZLPlayerEngineDelegate> delegate;
@property (nonatomic, readonly) ZLMediaInfo *info;
@property (nonatomic, readonly) double duration;  // 0 for live.
@property (nonatomic, readonly) BOOL paused;
@property (nonatomic, readonly) BOOL buffering;
@property (nonatomic, readonly) int audioIndex;
// The frames that the display did not show, because they came too late.
@property (nonatomic, readonly) NSUInteger droppedFrames;
// The cues of the text subtitles that the reads found. Set after start.
@property (nonatomic, readonly) ZLEmbeddedSubtitles *subtitles;

// The engine owns the input from now on.
- (instancetype)initWithInput:(ZLInput *)input info:(ZLMediaInfo *)info;

// Opens the decoders and starts the playback at a second.
- (BOOL)startAt:(double)seconds error:(NSError **)error;

// The second that plays now.
- (double)position;

- (void)setPaused:(BOOL)paused;
- (void)seekTo:(double)seconds;
- (void)selectAudioIndex:(int)index;

// Without video, for example when the app is in the background, the engine
// decodes only the audio.
- (void)setVideoEnabled:(BOOL)enabled;

// Returns the frame to show now, or nil when the shown frame stays. Call it
// from the display link on the main thread.
- (ZLVideoFrame *)frameToShow;

- (void)close;

@end
