#import "ZLLibraryRows.h"
#import "ZLAddonManager.h"
#import "ZLLibrary.h"

NSString *const ZLNewEpisodesDidChangeNotification = @"ZLNewEpisodesDidChange";

// The days in which an episode counts as new.
static const NSInteger ZLNewDays = 14;
// The series that one check asks the addons for.
static const NSUInteger ZLNewSeriesLimit = 10;

static NSArray *ZLNewItems;  // Pairs of ZLMeta and ZLEpisode.
static NSDate *ZLNewChecked;

@implementation ZLLibraryRow
@end

@implementation ZLLibraryRows

+ (ZLLibraryRow *)continueWatching {
    ZLLibrary *library = [ZLLibrary shared];
    NSMutableArray *metas = [NSMutableArray array], *badges = [NSMutableArray array];
    NSMutableArray *progress = [NSMutableArray array], *episodes = [NSMutableArray array];
    for (ZLLibraryItem *item in [library continueWatching]) {
        ZLEpisode *next = [item.meta.type isEqualToString:@"series"] ? [library nextEpisodeOf:item.meta] : nil;
        NSString *video = next.identifier ?: item.meta.identifier;
        [metas addObject:item.meta];
        [badges addObject:next ? [next code] : [NSNull null]];
        [progress addObject:@([library progressOf:video])];
        [episodes addObject:next ?: [NSNull null]];
    }
    ZLLibraryRow *row = [ZLLibraryRow new];
    row.title = @"Continue watching";
    row.metas = metas;
    row.badges = badges;
    row.progress = progress;
    row.episodes = episodes;
    return row;
}

+ (ZLLibraryRow *)watchlist {
    NSMutableArray *metas = [NSMutableArray array];
    for (ZLLibraryItem *item in [[ZLLibrary shared] watchlist]) [metas addObject:item.meta];
    ZLLibraryRow *row = [ZLLibraryRow new];
    row.title = @"Watchlist";
    row.metas = metas;
    return row;
}

+ (ZLLibraryRow *)newEpisodes {
    NSMutableArray *metas = [NSMutableArray array], *badges = [NSMutableArray array], *episodes = [NSMutableArray array];
    for (NSArray *pair in ZLNewItems) {
        ZLEpisode *episode = pair[1];
        if ([[ZLLibrary shared] isWatched:episode.identifier]) continue;
        [metas addObject:pair[0]];
        [badges addObject:[episode code]];
        [episodes addObject:episode];
    }
    ZLLibraryRow *row = [ZLLibraryRow new];
    row.title = @"New episodes";
    row.metas = metas;
    row.badges = badges;
    row.episodes = episodes;
    return row;
}

+ (void)refreshNewEpisodes {
    if (ZLNewChecked && -[ZLNewChecked timeIntervalSinceNow] < 6 * 3600) return;
    ZLNewChecked = [NSDate date];
    NSArray *series = [[ZLLibrary shared] series];
    if (series.count > ZLNewSeriesLimit) series = [series subarrayWithRange:NSMakeRange(0, ZLNewSeriesLimit)];
    __block NSUInteger left = series.count;
    NSMutableArray *found = [NSMutableArray array];
    for (ZLMeta *meta in series) {
        [[ZLAddonManager shared] loadMeta:meta.type identifier:meta.identifier completion:^(ZLMeta *full, NSError *error) {
            if (full) {
                // The library keeps the new list of episodes.
                ZLLibraryItem *item = [[ZLLibrary shared] itemFor:full.identifier];
                if (item) [[ZLLibrary shared] setMeta:full inWatchlist:item.inWatchlist];
                for (ZLEpisode *episode in [[ZLLibrary shared] newEpisodesOf:full days:ZLNewDays]) {
                    if (episode.season != 0) [found addObject:@[ full, episode ]];
                }
            }
            if (--left == 0) {
                [found sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
                    return [[b[1] released] compare:[a[1] released]];
                }];
                ZLNewItems = found;
                [[NSNotificationCenter defaultCenter] postNotificationName:ZLNewEpisodesDidChangeNotification object:nil];
            }
        }];
    }
}

@end
