#import "ZLStreamRank.h"

@implementation ZLRankedStreams
@end

ZLRankedStreams *ZLRankStreams(NSArray *streams, BOOL includeHeavy) {
    ZLRankedStreams *ranked = [ZLRankedStreams new];
    NSMutableArray *entries = [NSMutableArray array];
    NSUInteger heavy = 0, torrents = 0, order = 0;
    for (ZLStream *stream in streams) {
        order++;
        if (stream.isTorrent || !stream.URL) {
            if (stream.isTorrent) torrents++;
            continue;
        }
        ZLStreamInfo *info = [ZLStreamInfo infoForText:stream.allText];
        if ([info tooHeavy]) {
            heavy++;
            if (!includeHeavy) continue;
        }
        // The order of the addon breaks a tie, so the order stays stable.
        [entries addObject:@[ @([info score]), @(order), stream, info ]];
    }
    [entries sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
        NSComparisonResult byScore = [b[0] compare:a[0]];
        return byScore != NSOrderedSame ? byScore : [a[1] compare:b[1]];
    }];
    NSMutableArray *sorted = [NSMutableArray array], *infos = [NSMutableArray array];
    for (NSArray *entry in entries) {
        [sorted addObject:entry[2]];
        [infos addObject:entry[3]];
    }
    ranked.streams = sorted;
    ranked.infos = infos;
    ranked.heavy = heavy;
    ranked.torrents = torrents;
    return ranked;
}
