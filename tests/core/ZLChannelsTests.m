#import "ZLTest.h"
#import "ZLChannels.h"
#import "ZLStore.h"
#import "ZLTestServer.h"

static ZLStore *TemporaryStore(void) {
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    return [[ZLStore alloc] initWithDirectory:directory];
}

static ZLChannel *Channel(NSString *name, NSString *group) {
    ZLChannel *channel = [ZLChannel new];
    channel.name = name;
    channel.group = group;
    channel.URL = [NSURL URLWithString:[@"http://example.org/" stringByAppendingString:name]];
    return channel;
}

ZL_TEST(test_channels_fetch_a_list_and_an_hls_stream) {
    ZLTestServer *server = [ZLTestServer new];
    ZL_EXPECT([server start]);
    NSData *list = [@"#EXTM3U\n#EXTINF:-1 group-title=\"News\",One\none.ts\n#EXTINF:-1,Two\nhttp://example.org/two.m3u8\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSURL *listURL = [server serve:list at:@"/lists/tv.m3u8" type:@"application/vnd.apple.mpegurl"];
    NSData *hls = [@"#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,\nseg.ts\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSURL *hlsURL = [server serve:hls at:@"/live/news/index.m3u8" type:@"application/vnd.apple.mpegurl"];

    NSError *error = nil;
    NSArray *channels = ZLFetchChannels(listURL, &error);
    ZL_EQUAL_INT(channels.count, 2);
    ZL_EQUAL([channels[0] URL], [NSURL URLWithString:@"one.ts" relativeToURL:listURL].absoluteURL);
    ZL_EQUAL([channels[0] group], @"News");

    NSUInteger requests = server.requestCount;
    channels = ZLFetchChannels(hlsURL, &error);
    ZL_EQUAL_INT(channels.count, 1);
    ZL_EQUAL([channels[0] URL], hlsURL);
    ZL_EQUAL([channels[0] name], @"127.0.0.1");
    ZL_EQUAL_INT(server.requestCount, requests + 1);

    // A media link is one channel, with no fetch.
    channels = ZLFetchChannels([NSURL URLWithString:@"http://example.org/film/movie.mkv"], &error);
    ZL_EQUAL_INT(channels.count, 1);
    ZL_EQUAL([channels[0] name], @"movie");
    ZL_EQUAL_INT(server.requestCount, requests + 1);
    [server stop];
}

ZL_TEST(test_channels_have_groups_and_favourites) {
    ZLStore *store = TemporaryStore();
    ZLChannelList *list = [[ZLChannelList alloc] initWithStore:store];
    NSArray *channels = @[ Channel(@"a", @"News"), Channel(@"b", nil), Channel(@"c", @"Sport"), Channel(@"d", @"News") ];
    [list setChannels:channels failures:nil];
    ZL_EQUAL([list groups], (@[ @"News", @"Sport", @"Other" ]));
    ZL_EQUAL([[list channelsInGroup:@"News"] valueForKey:@"name"], (@[ @"a", @"d" ]));
    ZL_EQUAL([[list channelsInGroup:@"Other"] valueForKey:@"name"], (@[ @"b" ]));

    [list setChannel:channels[3] favourite:YES];
    [list setChannel:channels[0] favourite:YES];
    ZL_EXPECT([list isFavourite:channels[0]]);
    ZL_EXPECT(![list isFavourite:channels[1]]);
    // The favourites keep the order of the list.
    ZL_EQUAL([[list favourites] valueForKey:@"name"], (@[ @"a", @"d" ]));
    [list setChannel:channels[0] favourite:NO];
    [store flush];
    ZLChannelList *again = [[ZLChannelList alloc] initWithStore:[[ZLStore alloc] initWithDirectory:store.directory]];
    [again setChannels:channels failures:nil];
    ZL_EQUAL([[again favourites] valueForKey:@"name"], (@[ @"d" ]));
}
