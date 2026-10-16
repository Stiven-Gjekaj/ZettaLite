// Puts the streams of all addons in order for the stream picker and for
// autoplay. The best stream for the A5 chip comes first: H.264 at 1080p plays
// in hardware. Torrents and the streams that are too heavy go out.

#import <Foundation/Foundation.h>
#import "ZLMeta.h"
#import "ZLStreamInfo.h"

@interface ZLRankedStreams : NSObject
@property (nonatomic, copy) NSArray *streams;  // ZLStream, best first.
@property (nonatomic, copy) NSArray *infos;    // ZLStreamInfo of each stream.
@property (nonatomic) NSUInteger heavy;        // Streams out because they are too heavy.
@property (nonatomic) NSUInteger torrents;     // Streams out because they are torrents.
@end

// includeHeavy keeps the heavy streams, after the others.
ZLRankedStreams *ZLRankStreams(NSArray *streams, BOOL includeHeavy);
