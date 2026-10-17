#import "ZLTest.h"
#import "ZLAddonManager.h"
#import "ZLSources.h"
#import "ZLStore.h"
#import "ZLTestServer.h"

static NSData *JSON(id object) {
    return [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL];
}

ZL_TEST(test_fetch_json_reads_an_answer) {
    ZLTestServer *server = [ZLTestServer new];
    [server start];
    NSURL *url = [server serve:JSON(@{ @"metas": @[ @{ @"id": @"tt1", @"type": @"movie", @"name": @"One" } ] })
                            at:@"/catalog/movie/top.json" type:@"application/json"];
    __block BOOL done = NO;
    __block id answer = nil;
    ZLFetchJSON(url, ^(id json, NSError *error) {
        answer = json;
        done = YES;
    });
    ZL_EXPECT(ZLTestWait(&done, 10));
    ZL_EQUAL([[answer[@"metas"] firstObject] objectForKey:@"name"], @"One");
    [server stop];
}

ZL_TEST(test_fetch_json_reports_an_answer_that_is_not_json) {
    ZLTestServer *server = [ZLTestServer new];
    [server start];
    NSURL *url = [server serve:[@"<html>" dataUsingEncoding:NSUTF8StringEncoding] at:@"/x.json" type:@"text/html"];
    __block BOOL done = NO;
    __block NSError *failure = nil;
    ZLFetchJSON(url, ^(id json, NSError *error) {
        failure = error;
        done = YES;
    });
    ZL_EXPECT(ZLTestWait(&done, 10));
    ZL_EXPECT(failure != nil);
    [server stop];
}

ZL_TEST(test_fetch_puts_a_high_request_before_the_normal_ones_that_wait) {
    ZLTestServer *server = [ZLTestServer new];
    ZL_EXPECT([server start]);
    NSURL *url = [server serve:[@"{}" dataUsingEncoding:NSUTF8StringEncoding] at:@"/a.json" type:@"application/json"];
    // Each answer takes a moment, so that the normal requests wait in the queue.
    server.delay = 0.2;
    NSMutableArray *order = [NSMutableArray array];
    for (int i = 0; i < 12; i++) {
        ZLFetchJSON(url, ^(id json, NSError *error) { [order addObject:@"normal"]; });
    }
    ZLFetchJSONWithPriority(url, ZLFetchHigh, ^(id json, NSError *error) { [order addObject:@"high"]; });
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:10];
    while (order.count < 13 && [until timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    ZL_EQUAL_INT(order.count, 13);
    // At most 4 requests run at the same time. The high request starts next.
    NSUInteger high = [order indexOfObject:@"high"];
    ZL_EXPECT(high != NSNotFound && high < 8);
    [server stop];
}

