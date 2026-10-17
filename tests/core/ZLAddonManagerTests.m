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

static ZLStore *TemporaryStore(void) {
    return [[ZLStore alloc] initWithDirectory:[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]]];
}

// Runs the run loop until the condition is true, or for some seconds.
static BOOL WaitFor(BOOL (^condition)(void), NSTimeInterval seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!condition() && [until timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
    return condition();
}

static void RunFor(NSTimeInterval seconds) {
    WaitFor(^{ return NO; }, seconds);
}

// A test addon with a catalog for Home and ten catalogs with search.
static NSURL *ServeAddon(ZLTestServer *server) {
    NSMutableArray *catalogs = [NSMutableArray arrayWithObject:@{ @"type": @"movie", @"id": @"top", @"name": @"Top" }];
    for (int i = 0; i < 10; i++) {
        NSString *identifier = [NSString stringWithFormat:@"find%d", i];
        [catalogs addObject:@{ @"type": @"movie", @"id": identifier, @"name": identifier,
                               @"extra": @[ @{ @"name": @"search", @"isRequired": @YES } ] }];
        for (NSString *query in @[ @"a", @"b" ]) {
            [server serve:JSON(@{ @"metas": @[ @{ @"id": [@"tt" stringByAppendingString:query], @"type": @"movie", @"name": query } ] })
                       at:[NSString stringWithFormat:@"/catalog/movie/%@/search=%@.json", identifier, query] type:@"application/json"];
        }
    }
    [server serve:JSON(@{ @"metas": @[ @{ @"id": @"tt1", @"type": @"movie", @"name": @"One" } ] })
               at:@"/catalog/movie/top.json" type:@"application/json"];
    return [server serve:JSON(@{ @"id": @"test", @"name": @"Test", @"types": @[ @"movie" ], @"resources": @[ @"catalog" ], @"catalogs": catalogs })
                      at:@"/manifest.json" type:@"application/json"];
}

static ZLAddonManager *Manager(ZLStore *store, NSURL *manifest) {
    ZLSourceList *sources = [[ZLSourceList alloc] initWithStore:store];
    [sources setText:manifest.absoluteString];
    return [[ZLAddonManager alloc] initWithStore:store sources:sources];
}

ZL_TEST(test_manager_asks_for_a_manifest_again_only_when_it_is_old) {
    ZLTestServer *server = [ZLTestServer new];
    ZL_EXPECT([server start]);
    NSURL *manifest = ServeAddon(server);
    ZLStore *store = TemporaryStore();
    ZLAddonManager *manager = Manager(store, manifest);
    [manager reload];
    ZL_EXPECT(WaitFor(^{ return (BOOL)(manager.addons.count == 1 && server.requestCount == 1); }, 10));
    RunFor(0.2);

    // A start a moment later uses the manifest on the phone.
    ZLAddonManager *again = Manager(store, manifest);
    [again reload];
    ZL_EQUAL_INT(again.addons.count, 1);
    RunFor(0.5);
    ZL_EQUAL_INT(server.requestCount, 1);

    // A refresh asks again.
    [again refresh];
    ZL_EXPECT(WaitFor(^{ return (BOOL)(server.requestCount == 2); }, 10));

    // A manifest older than 6 hours is asked again.
    [store setObject:@{ manifest.absoluteString: @([[NSDate date] timeIntervalSince1970] - 7 * 3600) } named:@"manifestDates"];
    ZLAddonManager *later = Manager(store, manifest);
    [later reload];
    ZL_EXPECT(WaitFor(^{ return (BOOL)(server.requestCount == 3); }, 10));
    [server stop];
}

