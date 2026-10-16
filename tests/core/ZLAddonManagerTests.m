#import "ZLTest.h"
#import "ZLAddonManager.h"
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
