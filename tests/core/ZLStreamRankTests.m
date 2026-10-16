#import "ZLTest.h"
#import "ZLStreamRank.h"

static ZLStream *Stream(NSString *url, NSString *title) {
    NSMutableDictionary *json = [NSMutableDictionary dictionaryWithObject:title forKey:@"title"];
    if (url) json[@"url"] = url;
    else json[@"infoHash"] = @"abc";
    return [ZLStream streamWithJSON:json];
}

ZL_TEST(test_rank_puts_hardware_1080p_first_and_drops_the_rest) {
    NSArray *streams = @[
        Stream(@"http://a/1", @"Film.2160p.HDR.x265"),
        Stream(@"http://a/2", @"Film.720p.x264"),
        Stream(nil, @"Film.1080p.x264 torrent"),
        Stream(@"http://a/3", @"Film.1080p.WEB.x264"),
        Stream(@"http://a/4", @"Film.480p.x265"),
        Stream(@"http://a/5", @"Film.1080p.x265.10bit"),
    ];
    ZLRankedStreams *ranked = ZLRankStreams(streams, NO);
    ZL_EQUAL_INT(ranked.streams.count, 3);
    ZL_EQUAL([[ranked.streams[0] URL] absoluteString], @"http://a/3");
    ZL_EQUAL([[ranked.streams[1] URL] absoluteString], @"http://a/2");
    ZL_EQUAL([[ranked.streams[2] URL] absoluteString], @"http://a/4");
    ZL_EQUAL_INT(ranked.heavy, 2);
    ZL_EQUAL_INT(ranked.torrents, 1);
    ZLRankedStreams *all = ZLRankStreams(streams, YES);
    ZL_EQUAL_INT(all.streams.count, 5);
    ZL_EXPECT([[all.infos lastObject] tooHeavy]);
}
