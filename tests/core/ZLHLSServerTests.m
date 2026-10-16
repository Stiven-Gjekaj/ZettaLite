#import "ZLTest.h"
#import "ZLHLSServer.h"

@interface StaticSource : NSObject <ZLHLSSource>
@end

@implementation StaticSource

- (NSData *)playlist {
    return [@"#EXTM3U\n" dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSData *)segmentAtIndex:(NSUInteger)index error:(NSError **)error {
    if (index > 1) return nil;
    NSMutableData *data = [NSMutableData dataWithLength:300000];
    memset(data.mutableBytes, (int)index + 1, data.length);
    return data;
}

@end

static NSData *Get(NSURL *url, NSInteger *status, NSString **type) {
    NSHTTPURLResponse *response = nil;
    NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                         timeoutInterval:5];
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:(NSURLResponse **)&response error:NULL];
    *status = response.statusCode;
    if (type) *type = response.allHeaderFields[@"Content-Type"];
    return data;
}

ZL_TEST(test_server_serves_playlist_and_segments) {
    ZLHLSServer *server = [ZLHLSServer new];
    NSError *error = nil;
    ZL_EXPECT([server start:&error]);
    ZL_EXPECT(server.port > 0);
    StaticSource *source = [StaticSource new];
    NSURL *playlist = [server addSource:source];
    ZL_EQUAL(playlist.host, @"127.0.0.1");
    ZL_EQUAL(playlist.lastPathComponent, @"index.m3u8");

    NSInteger status = 0;
    NSString *type = nil;
    NSData *body = Get(playlist, &status, &type);
    ZL_EQUAL_INT(status, 200);
    ZL_EQUAL(type, @"application/vnd.apple.mpegurl");
    ZL_EQUAL(body, [source playlist]);

    NSData *segment = Get([NSURL URLWithString:@"1.ts" relativeToURL:playlist], &status, &type);
    ZL_EQUAL_INT(status, 200);
    ZL_EQUAL(type, @"video/mp2t");
    ZL_EQUAL_INT(segment.length, 300000);
    ZL_EQUAL_INT(((const uint8_t *)segment.bytes)[299999], 2);
    [server stop];
}

ZL_TEST(test_server_refuses_unknown_paths) {
    ZLHLSServer *server = [ZLHLSServer new];
    [server start:NULL];
    NSURL *playlist = [server addSource:[StaticSource new]];
    NSInteger status = 0;
    Get([NSURL URLWithString:@"9.ts" relativeToURL:playlist], &status, NULL);
    ZL_EQUAL_INT(status, 502);
    Get([NSURL URLWithString:@"x1.ts" relativeToURL:playlist], &status, NULL);
    ZL_EQUAL_INT(status, 502);
    Get([NSURL URLWithString:@"other.txt" relativeToURL:playlist], &status, NULL);
    ZL_EQUAL_INT(status, 404);
    NSString *missing = [NSString stringWithFormat:@"http://127.0.0.1:%u/nothing/index.m3u8", server.port];
    Get([NSURL URLWithString:missing], &status, NULL);
    ZL_EQUAL_INT(status, 404);
    [server stop];
}

ZL_TEST(test_server_forgets_removed_source) {
    ZLHLSServer *server = [ZLHLSServer new];
    [server start:NULL];
    StaticSource *source = [StaticSource new];
    NSURL *playlist = [server addSource:source];
    [server removeSource:source];
    NSInteger status = 0;
    Get(playlist, &status, NULL);
    ZL_EQUAL_INT(status, 404);
    [server stop];
}
