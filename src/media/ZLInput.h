// Opens a media URL with FFmpeg. Each byte comes through ZLHTTPStream, also
// for the playlists and the segments that an HLS or DASH demuxer opens, so
// that the app controls the headers and the trust.
// The methods block. Do not call them on the main thread.

#import <Foundation/Foundation.h>
#include <libavformat/avformat.h>

@interface ZLInput : NSObject

@property (nonatomic, readonly) AVFormatContext *context;
@property (nonatomic, readonly) NSURL *URL;
@property (nonatomic, readonly, copy) NSDictionary *headers;
// YES when the input can seek, for example a file on a server with Range.
@property (nonatomic, readonly) BOOL seekable;

// Opens the input and reads the stream information. A file URL also works.
+ (instancetype)openURL:(NSURL *)url headers:(NSDictionary *)headers error:(NSError **)error;

// Stops each read that waits. Then each FFmpeg call returns an error.
- (void)cancel;
- (void)close;

@end

// Makes an NSError from an FFmpeg error code.
NSError *ZLAVError(int code, NSString *text);
