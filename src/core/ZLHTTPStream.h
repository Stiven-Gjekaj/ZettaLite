// Reads one HTTP resource as a stream of bytes, with seek. FFmpeg reads each
// URL through this class, so that the app controls the headers and the trust.
//
// One connection reads ahead from the read position. A seek to a far
// position starts a new connection with a Range header. When the connection
// is far ahead of the reader, it stops, and it starts again later.
// The read methods block. Do not call them on the main thread.

#import <Foundation/Foundation.h>
#import "ZLTrust.h"

@interface ZLHTTPStream : NSObject

@property (nonatomic, readonly) NSURL *URL;
// The URL after redirects. Relative links in a playlist use it.
@property (nonatomic, readonly) NSURL *finalURL;
// -1 when the server does not give a length.
@property (nonatomic, readonly) int64_t length;
// YES when the server accepts Range requests.
@property (nonatomic, readonly) BOOL seekable;
@property (nonatomic, readonly) NSString *contentType;
@property (nonatomic, readonly) int64_t position;

// Seconds that a read waits for new bytes before it fails. The default is 30.
@property (nonatomic) NSTimeInterval timeout;

- (instancetype)initWithURL:(NSURL *)url headers:(NSDictionary *)headers;
- (instancetype)initWithURL:(NSURL *)url headers:(NSDictionary *)headers trust:(ZLTrust *)trust;

// Connects and waits for the response head.
- (BOOL)open:(NSError **)error;

// Returns the number of bytes read, 0 at the end, or -1 on an error.
- (NSInteger)read:(uint8_t *)bytes length:(NSUInteger)length error:(NSError **)error;

- (BOOL)seekTo:(int64_t)offset error:(NSError **)error;

// Stops the connection. A read that waits returns -1.
- (void)close;

// Reads the full resource. It is for small files, for example a playlist.
// After a connection or TLS error it tries one more time. After an HTTP
// status error it does not.
+ (NSData *)fetch:(NSURL *)url headers:(NSDictionary *)headers finalURL:(NSURL **)finalURL error:(NSError **)error;

@end
