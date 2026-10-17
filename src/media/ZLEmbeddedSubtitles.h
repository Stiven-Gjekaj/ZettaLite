// The text subtitles inside a media file. The players give each packet that
// they read to this object, and it keeps the cues of each text subtitle
// stream. The subtitle packets are small, so the players read all of them,
// and a change of the track shows the cues that were already read.
// Bitmap subtitles, for example PGS and DVD, are not read.

#import <Foundation/Foundation.h>
#include <libavformat/avformat.h>
#import "ZLSubtitles.h"

// YES for a subtitle codec that this object reads.
BOOL ZLIsTextSubtitleCodec(enum AVCodecID codec);

@interface ZLEmbeddedSubtitles : NSObject

// Turns on the text subtitle streams of the context. origin is the start of
// the media in seconds of the input. The cues use seconds from the origin.
- (instancetype)initWithContext:(AVFormatContext *)context origin:(double)origin;

// The stream indexes of the text subtitle streams.
- (NSArray *)indexes;

// Keeps the cue of a subtitle packet. Returns NO for a packet of another stream.
- (BOOL)takePacket:(AVPacket *)packet;

- (ZLCueList *)cuesOfStream:(int)index;

@end
