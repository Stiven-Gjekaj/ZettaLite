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
// When YES, a full body comes with chunked transfer encoding.
@property (nonatomic) BOOL chunked;
// Bytes per write. A small value makes a slow server.
@property (nonatomic) NSUInteger chunkSize;

- (BOOL)start;
- (void)stop;
// path is for example "/a.mkv". Returns the full URL.
- (NSURL *)serve:(NSData *)body at:(NSString *)path type:(NSString *)type;
- (NSURL *)redirect:(NSString *)path to:(NSString *)target;

@end

// Bytes with a pattern, so that a test can find the offset of each byte.
NSData *ZLTestPattern(NSUInteger length);
