// Changes audio that the system player of iOS 6 cannot play (AC3, E-AC3,
// DTS, TrueHD, Opus, Vorbis, FLAC, and others) into stereo AAC at 48 kHz.
//
// Each HLS segment has its own encoder. The AAC frames sit on one grid of
// 1024 samples from time 0, so that the frames of two segments meet without
// a gap. A segment also encodes 2 frames before its start and 2 frames after
// its end, and then drops them, so that the frames at each edge are complete.

#import <Foundation/Foundation.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>

// The sample rate and the frame size of the AAC output.
extern const int ZLAACSampleRate;
extern const int ZLAACFrameSize;

@interface ZLAudioEncoder : NSObject

// The parameters of the AAC stream, for the muxer.
@property (nonatomic, readonly) AVCodecParameters *outputParameters;

// source is the audio stream of the input.
- (instancetype)initWithStream:(AVStream *)source error:(NSError **)error;

// Starts a segment that covers [start, end) seconds of the input. end can be
// INFINITY for the last segment.
- (BOOL)beginSegmentFrom:(double)start to:(double)end error:(NSError **)error;

// The first second that the segment needs from the input, with the frames
// before the start.
- (double)inputStart;

// Gives one packet of the input. Packets outside the segment are ignored.
- (BOOL)addPacket:(AVPacket *)packet error:(NSError **)error;

// YES when the encoder has all the input that the segment needs.
- (BOOL)hasEnoughInput;

// Finishes the segment. Returns the AAC packets, with pts in 1/48000 units
// of the input time.
- (NSArray *)finishSegment:(NSError **)error;

@end

// One AAC packet. It holds a copy of the data.
@interface ZLEncodedPacket : NSObject
@property (nonatomic) int64_t pts;
@property (nonatomic) int64_t duration;
@property (nonatomic, strong) NSData *data;
@end
