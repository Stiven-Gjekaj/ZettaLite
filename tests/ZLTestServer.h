// A small HTTP server for the tests. It serves bytes from memory and it
// answers Range requests, as a media server does.

#import <Foundation/Foundation.h>

@interface ZLTestServer : NSObject

@property (nonatomic, readonly) uint16_t port;
// The head of the last request, with the header names in lower case.
@property (nonatomic, readonly) NSDictionary *lastHeaders;
@property (nonatomic, readonly) NSUInteger requestCount;
// When NO, the server ignores Range and sends the full body with 200.
@property (nonatomic) BOOL acceptsRanges;
// When NO, the server sends no length and ignores Range, as a live stream does.
@property (nonatomic) BOOL sendsLength;
// When YES, a full body comes with chunked transfer encoding.
@property (nonatomic) BOOL chunked;
// The number of the next requests that get no answer: the server closes the
// connection after it reads the request.
@property (atomic) NSUInteger dropsRequests;
// Seconds that the server waits before each answer.
@property (atomic) NSTimeInterval delay;
// When YES, the server keeps a connection open for the next request, when
// the request asks for it.
@property (atomic) BOOL keepsAlive;
// When YES, the server compresses a full body with gzip, when the request
// accepts it.
@property (atomic) BOOL gzips;
// The number of connections that the server accepted.
@property (atomic, readonly) NSUInteger connectionCount;
// Bytes per write. A small value makes a slow server.
@property (nonatomic) NSUInteger chunkSize;

- (BOOL)start;
- (void)stop;
// path is for example "/a.mkv". Returns the full URL.
- (NSURL *)serve:(NSData *)body at:(NSString *)path type:(NSString *)type;
- (NSURL *)redirect:(NSString *)path to:(NSString *)target;
// Closes the connections that wait for a next request, as a server does
// after its keep-alive time.
- (void)closeIdleConnections;

@end

// Bytes with a pattern, so that a test can find the offset of each byte.
NSData *ZLTestPattern(NSUInteger length);
