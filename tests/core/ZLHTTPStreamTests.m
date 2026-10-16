#import "ZLTest.h"
#import "ZLHTTPStream.h"
#import "ZLTestServer.h"

static NSData *ReadAll(ZLHTTPStream *stream, NSUInteger chunk) {
    NSMutableData *data = [NSMutableData data];
    uint8_t *buffer = malloc(chunk);
    while (YES) {
        NSInteger count = [stream read:buffer length:chunk error:NULL];
        if (count <= 0) break;
        [data appendBytes:buffer length:(NSUInteger)count];
    }
    free(buffer);
    return data;
}

ZL_TEST(test_stream_reads_a_full_file_and_knows_its_length) {
    ZLTestServer *server = [ZLTestServer new];
    ZL_EXPECT([server start]);
    NSData *body = ZLTestPattern(3 * 1024 * 1024 + 17);
    NSURL *url = [server serve:body at:@"/a.mkv" type:@"video/x-matroska"];
    ZLHTTPStream *stream = [[ZLHTTPStream alloc] initWithURL:url headers:nil];
    ZL_EXPECT([stream open:NULL]);
    ZL_EQUAL_INT(stream.length, body.length);
    ZL_EXPECT(stream.seekable);
    ZL_EQUAL(stream.contentType, @"video/x-matroska");
    ZL_EXPECT([ReadAll(stream, 100000) isEqualToData:body]);
    [stream close];
    [server stop];
}

ZL_TEST(test_stream_seeks_far_and_near) {
    ZLTestServer *server = [ZLTestServer new];
    [server start];
    NSData *body = ZLTestPattern(4 * 1024 * 1024);
    NSURL *url = [server serve:body at:@"/b.mp4" type:@"video/mp4"];
    ZLHTTPStream *stream = [[ZLHTTPStream alloc] initWithURL:url headers:nil];
    ZL_EXPECT([stream open:NULL]);
    uint8_t bytes[1000];
    int64_t offsets[] = {3000000, 3000500, 10, 2000000, 4 * 1024 * 1024 - 400};
    for (int i = 0; i < 5; i++) {
        ZL_EXPECT([stream seekTo:offsets[i] error:NULL]);
        NSInteger count = [stream read:bytes length:sizeof(bytes) error:NULL];
        ZL_EXPECT(count > 0);
        ZL_EXPECT(memcmp(bytes, (const uint8_t *)body.bytes + offsets[i], (size_t)count) == 0);
    }
    [stream seekTo:body.length error:NULL];
    ZL_EQUAL_INT([stream read:bytes length:sizeof(bytes) error:NULL], 0);
    [stream close];
    [server stop];
}

ZL_TEST(test_stream_sends_the_headers_also_after_a_redirect) {
    ZLTestServer *server = [ZLTestServer new];
    [server start];
    NSURL *target = [server serve:ZLTestPattern(1000) at:@"/c.ts" type:@"video/mp2t"];
    NSURL *url = [server redirect:@"/go" to:target.absoluteString];
    ZLHTTPStream *stream = [[ZLHTTPStream alloc] initWithURL:url headers:@{ @"Referer": @"https://example.org/" }];
    ZL_EXPECT([stream open:NULL]);
    ZL_EQUAL(server.lastHeaders[@"referer"], @"https://example.org/");
    ZL_EQUAL(stream.finalURL.path, @"/c.ts");
    [stream close];
    [server stop];
}

ZL_TEST(test_stream_skips_to_the_offset_when_the_server_ignores_ranges) {
    ZLTestServer *server = [ZLTestServer new];
    server.acceptsRanges = NO;
    [server start];
    NSData *body = ZLTestPattern(2 * 1024 * 1024);
    NSURL *url = [server serve:body at:@"/d.ts" type:@"video/mp2t"];
    ZLHTTPStream *stream = [[ZLHTTPStream alloc] initWithURL:url headers:nil];
    ZL_EXPECT([stream open:NULL]);
    ZL_EXPECT(!stream.seekable);
    [stream seekTo:1500000 error:NULL];
    uint8_t bytes[100];
    NSInteger count = [stream read:bytes length:sizeof(bytes) error:NULL];
    ZL_EQUAL_INT(count, 100);
    ZL_EXPECT(memcmp(bytes, (const uint8_t *)body.bytes + 1500000, 100) == 0);
    [stream close];
    [server stop];
}

ZL_TEST(test_stream_reports_an_http_error) {
    ZLTestServer *server = [ZLTestServer new];
    [server start];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%u/none", server.port]];
    NSError *error = nil;
    ZL_EXPECT(![[[ZLHTTPStream alloc] initWithURL:url headers:nil] open:&error]);
    ZL_EQUAL_INT(error.code, ZLErrorHTTPStatus);
    [server stop];
}

ZL_TEST(test_fetch_reads_a_small_file) {
    ZLTestServer *server = [ZLTestServer new];
    [server start];
    NSData *body = [@"#EXTM3U\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSURL *url = [server serve:body at:@"/list.m3u" type:@"audio/x-mpegurl"];
    NSURL *final = nil;
    ZL_EQUAL([ZLHTTPStream fetch:url headers:nil finalURL:&final error:NULL], body);
    ZL_EQUAL(final, url);
    [server stop];
}
