// A small HTTP server on 127.0.0.1 for the HLS player of the system.
// iOS 6 does not play HLS from a file URL, so the app serves it here.
// A path is /<session>/index.m3u8 or /<session>/<n>.ts.

#import <Foundation/Foundation.h>

// The source of an HLS stream for ZLHLSServer.
@protocol ZLHLSSource <NSObject>
// The playlist. It can block until the source knows its segments.
- (NSData *)playlist;
// Returns the TS data of the segment, or nil. It can block.
- (NSData *)segmentAtIndex:(NSUInteger)index error:(NSError **)error;
@end

@interface ZLHLSServer : NSObject

@property (nonatomic, readonly) uint16_t port;

+ (instancetype)shared;

// Opens the socket on a free port. Returns NO if it cannot.
- (BOOL)start:(NSError **)error;
- (void)stop;

// Adds a source and returns the URL of its playlist.
- (NSURL *)addSource:(id<ZLHLSSource>)source;
- (void)removeSource:(id<ZLHLSSource>)source;

@end
