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

ZL_TEST(test_stream_seeks_when_the_server_ignores_ranges) {
    ZLTestServer *server = [ZLTestServer new];
    server.acceptsRanges = NO;
    [server start];
    NSData *body = ZLTestPattern(2 * 1024 * 1024);
    NSURL *url = [server serve:body at:@"/d.ts" type:@"video/mp2t"];
    ZLHTTPStream *stream = [[ZLHTTPStream alloc] initWithURL:url headers:nil];
    ZL_EXPECT([stream open:NULL]);
    // A seek starts again from the start of the file, so it still works.
    ZL_EXPECT(stream.seekable);
    uint8_t bytes[100];
    int64_t offsets[] = {1500000, 100, 1900000};
    for (int i = 0; i < 3; i++) {
        [stream seekTo:offsets[i] error:NULL];
        NSInteger count = [stream read:bytes length:sizeof(bytes) error:NULL];
        ZL_EQUAL_INT(count, 100);
        ZL_EXPECT(memcmp(bytes, (const uint8_t *)body.bytes + offsets[i], 100) == 0);
    }
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

ZL_TEST(test_stream_reads_a_chunked_body) {
    ZLTestServer *server = [ZLTestServer new];
    server.chunked = YES;
    [server start];
    NSData *body = ZLTestPattern(25500);
    NSURL *url = [server serve:body at:@"/addon.json" type:@"application/json"];
    ZL_EQUAL([ZLHTTPStream fetch:url headers:nil finalURL:NULL error:NULL], body);
    [server stop];
}

// The TLS of iOS 6 cannot speak to this server: it accepts only AES-GCM, and
// its certificate comes from Let's Encrypt.
ZL_TEST(test_stream_speaks_modern_tls) {
    ZL_LIVE_ONLY();
    NSURL *url = [NSURL URLWithString:@"https://download.samplelib.com/mp4/sample-5s.mp4"];
    ZLHTTPStream *stream = [[ZLHTTPStream alloc] initWithURL:url headers:nil];
    NSError *error = nil;
    ZL_EXPECT([stream open:&error]);
    if (error) NSLog(@"%@", error);
    uint8_t bytes[16];
    ZL_EQUAL_INT([stream read:bytes length:sizeof(bytes) error:NULL], 16);
    // An MP4 file has "ftyp" at byte 4.
    ZL_EXPECT(memcmp(bytes + 4, "ftyp", 4) == 0);
    [stream close];
}

ZL_TEST(test_stream_asks_for_a_range_from_the_start) {
    ZLTestServer *server = [ZLTestServer new];
    [server start];
    NSURL *url = [server serve:ZLTestPattern(5000) at:@"/e.mp4" type:@"video/mp4"];
    ZLHTTPStream *stream = [[ZLHTTPStream alloc] initWithURL:url headers:nil];
    ZL_EXPECT([stream open:NULL]);
    ZL_EQUAL(server.lastHeaders[@"range"], @"bytes=0-");
    ZL_EXPECT(stream.seekable);
    ZL_EQUAL_INT(stream.length, 5000);
    [stream close];
    [server stop];
}

ZL_TEST(test_fetch_tries_again_after_a_dropped_connection) {
    ZLTestServer *server = [ZLTestServer new];
    ZL_EXPECT([server start]);
    NSData *body = [@"{\"id\":\"x\"}" dataUsingEncoding:NSUTF8StringEncoding];
    NSURL *url = [server serve:body at:@"/manifest.json" type:@"application/json"];
    server.dropsRequests = 1;
    NSError *error = nil;
    ZL_EQUAL([ZLHTTPStream fetch:url headers:nil finalURL:NULL error:&error], body);
    ZL_EQUAL_INT(server.requestCount, 2);
    // Two drops in a row fail: the fetch tries one more time only.
    server.dropsRequests = 2;
    ZL_EXPECT([ZLHTTPStream fetch:url headers:nil finalURL:NULL error:&error] == nil);
    ZL_EXPECT(error != nil);
    ZL_EQUAL_INT(server.requestCount, 4);
    [server stop];
}

ZL_TEST(test_fetch_does_not_try_again_after_an_http_error) {
    ZLTestServer *server = [ZLTestServer new];
    ZL_EXPECT([server start]);
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%u/none.json", server.port]];
    NSError *error = nil;
    ZL_EXPECT([ZLHTTPStream fetch:url headers:nil finalURL:NULL error:&error] == nil);
    ZL_EQUAL_INT(error.code, ZLErrorHTTPStatus);
    ZL_EQUAL_INT(server.requestCount, 1);
    [server stop];
}

ZL_TEST(test_fetch_uses_one_connection_for_many_requests) {
    ZLTestServer *server = [ZLTestServer new];
    server.keepsAlive = YES;
    ZL_EXPECT([server start]);
    NSData *body = ZLTestPattern(5000);
    NSURL *url = [server serve:body at:@"/a.json" type:@"application/json"];
    for (int i = 0; i < 3; i++) ZL_EQUAL([ZLHTTPStream fetch:url headers:nil finalURL:NULL error:NULL], body);
    ZL_EQUAL_INT(server.requestCount, 3);
    ZL_EQUAL_INT(server.connectionCount, 1);
    // A chunked answer also keeps the connection.
    server.chunked = YES;
    ZL_EQUAL([ZLHTTPStream fetch:url headers:nil finalURL:NULL error:NULL], body);
    ZL_EQUAL_INT(server.connectionCount, 1);
    [server stop];
}

ZL_TEST(test_fetch_connects_again_when_the_server_closed_the_idle_connection) {
    ZLTestServer *server = [ZLTestServer new];
    server.keepsAlive = YES;
    ZL_EXPECT([server start]);
    NSData *body = ZLTestPattern(100);
    NSURL *url = [server serve:body at:@"/a.json" type:@"application/json"];
    ZL_EQUAL([ZLHTTPStream fetch:url headers:nil finalURL:NULL error:NULL], body);
    [server closeIdleConnections];
    [NSThread sleepForTimeInterval:0.1];
    ZL_EQUAL([ZLHTTPStream fetch:url headers:nil finalURL:NULL error:NULL], body);
    ZL_EQUAL_INT(server.connectionCount, 2);
    // A server that closes after each answer gets a new connection each time.
    // The first of these fetches still uses the open connection.
    server.keepsAlive = NO;
    for (int i = 0; i < 3; i++) ZL_EQUAL([ZLHTTPStream fetch:url headers:nil finalURL:NULL error:NULL], body);
    ZL_EQUAL_INT(server.connectionCount, 4);
    [server stop];
}

ZL_TEST(test_fetch_asks_for_gzip_and_inflates_it) {
    ZLTestServer *server = [ZLTestServer new];
    server.gzips = YES;
    ZL_EXPECT([server start]);
    NSMutableString *text = [NSMutableString string];
    for (int i = 0; i < 2000; i++) [text appendFormat:@"{\"id\":\"tt%07d\",\"name\":\"Title %d\"},", i, i];
    NSData *body = [text dataUsingEncoding:NSUTF8StringEncoding];
    NSURL *url = [server serve:body at:@"/catalog.json" type:@"application/json"];
    ZL_EQUAL([ZLHTTPStream fetch:url headers:nil finalURL:NULL error:NULL], body);
    ZL_EQUAL(server.lastHeaders[@"accept-encoding"], @"gzip");
    server.chunked = YES;
    ZL_EQUAL([ZLHTTPStream fetch:url headers:nil finalURL:NULL error:NULL], body);
    [server stop];
}

