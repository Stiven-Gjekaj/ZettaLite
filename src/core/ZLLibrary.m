#import "ZLLibrary.h"
#import "ZLJSON.h"
#import "ZLStore.h"

NSString *const ZLLibraryDidChangeNotification = @"ZLLibraryDidChange";
const double ZLWatchedPart = 0.9;

@implementation ZLLibraryItem

- (double)progress {
    return self.duration > 0 ? MIN(1, self.position / self.duration) : 0;
}

@end

@interface ZLLibrary ()
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) ZLStore *store;
// The library as JSON: "titles": id -> title, "videos": video -> progress.
@property (nonatomic, strong) NSMutableDictionary *data;
@end

@implementation ZLLibrary

+ (instancetype)shared {
    static ZLLibrary *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[ZLLibrary alloc] initWithStoreName:@"library" store:[ZLStore shared]]; });
    return shared;
}

- (instancetype)initWithStoreName:(NSString *)name store:(id)store {
    if ((self = [super init])) {
        _name = [name copy];
        _store = store;
        NSDictionary *saved = [store objectNamed:name];
        _data = [NSMutableDictionary dictionary];
        [self load:saved];
    }
    return self;
}

- (void)load:(NSDictionary *)saved {
    self.data[@"titles"] = [ZLJSONDictionary(saved, @"titles") mutableCopy] ?: [NSMutableDictionary dictionary];
    self.data[@"videos"] = [ZLJSONDictionary(saved, @"videos") mutableCopy] ?: [NSMutableDictionary dictionary];
    for (NSString *key in [self.data[@"titles"] allKeys]) self.data[@"titles"][key] = [self.data[@"titles"][key] mutableCopy];
    for (NSString *key in [self.data[@"videos"] allKeys]) self.data[@"videos"][key] = [self.data[@"videos"][key] mutableCopy];
}

- (NSMutableDictionary *)titles {
    return self.data[@"titles"];
}

- (NSMutableDictionary *)videos {
    return self.data[@"videos"];
}

- (void)save {
    [self.store setObject:self.data named:self.name];
    [[NSNotificationCenter defaultCenter] postNotificationName:ZLLibraryDidChangeNotification object:self];
}

// The fields of a title that the library keeps. The episodes stay, so that
// the next episode works with no network.
static NSDictionary *ZLKeptJSON(ZLMeta *meta) {
    NSMutableDictionary *json = [NSMutableDictionary dictionary];
    for (NSString *key in @[ @"id", @"type", @"name", @"poster", @"background", @"releaseInfo", @"imdbRating", @"videos" ]) {
        if (meta.json[key]) json[key] = meta.json[key];
    }
    json[@"id"] = meta.identifier;
    json[@"type"] = meta.type;
    json[@"name"] = meta.name;
    return json;
}

- (NSMutableDictionary *)entryFor:(ZLMeta *)meta {
    NSMutableDictionary *entry = self.titles[meta.identifier];
    if (!entry) {
        entry = [NSMutableDictionary dictionary];
        self.titles[meta.identifier] = entry;
    }
    // A full title has episodes. Keep them when a smaller copy comes.
    NSDictionary *json = ZLKeptJSON(meta);
    if (!json[@"videos"] && entry[@"meta"][@"videos"]) {
        NSMutableDictionary *merged = [json mutableCopy];
        merged[@"videos"] = entry[@"meta"][@"videos"];
        json = merged;
    }
    entry[@"meta"] = json;
    return entry;
}

- (ZLLibraryItem *)itemFromEntry:(NSDictionary *)entry {
    ZLMeta *meta = [ZLMeta metaWithJSON:entry[@"meta"]];
    if (!meta) return nil;
    ZLLibraryItem *item = [ZLLibraryItem new];
    item.meta = meta;
    item.inWatchlist = [entry[@"watchlist"] boolValue];
    item.lastWatched = entry[@"watched"] ? [NSDate dateWithTimeIntervalSince1970:[entry[@"watched"] doubleValue]] : nil;
    item.lastVideo = entry[@"lastVideo"];
    NSDictionary *video = item.lastVideo ? self.videos[item.lastVideo] : nil;
    item.position = [video[@"position"] doubleValue];
    item.duration = [video[@"duration"] doubleValue];
    return item;
}

- (ZLLibraryItem *)itemFor:(NSString *)identifier {
    NSDictionary *entry = self.titles[identifier];
    return entry ? [self itemFromEntry:entry] : nil;
}

- (BOOL)isInWatchlist:(NSString *)identifier {
    return [self.titles[identifier][@"watchlist"] boolValue];
}

- (void)setMeta:(ZLMeta *)meta inWatchlist:(BOOL)inWatchlist {
    NSMutableDictionary *entry = [self entryFor:meta];
    entry[@"watchlist"] = @(inWatchlist);
    if (inWatchlist) entry[@"added"] = @([[NSDate date] timeIntervalSince1970]);
    [self save];
}

- (void)updateMeta:(ZLMeta *)meta {
    if (!self.titles[meta.identifier]) return;
    [self entryFor:meta];
    [self save];
}

- (void)recordMeta:(ZLMeta *)meta video:(NSString *)video position:(double)position duration:(double)duration {
    if (!video.length) return;
    NSMutableDictionary *entry = [self entryFor:meta];
    entry[@"watched"] = @([[NSDate date] timeIntervalSince1970]);
    entry[@"lastVideo"] = video;
    NSMutableDictionary *progress = self.videos[video] ?: [NSMutableDictionary dictionary];
    progress[@"position"] = @(MAX(0, position));
    if (duration > 0) progress[@"duration"] = @(duration);
    if (duration > 0 && position >= duration * ZLWatchedPart) progress[@"done"] = @YES;
    self.videos[video] = progress;
    [self save];
}

- (BOOL)isWatched:(NSString *)video {
    return video && [self.videos[video][@"done"] boolValue];
}

- (void)setVideo:(NSString *)video ofMeta:(ZLMeta *)meta watched:(BOOL)watched {
    if (!video.length) return;
    NSMutableDictionary *entry = [self entryFor:meta];
    NSMutableDictionary *progress = self.videos[video] ?: [NSMutableDictionary dictionary];
    progress[@"done"] = @(watched);
    progress[@"position"] = @0;
    self.videos[video] = progress;
    if (watched) {
        entry[@"watched"] = @([[NSDate date] timeIntervalSince1970]);
        entry[@"lastVideo"] = video;
    }
    [self save];
}

- (double)positionOf:(NSString *)video {
    NSDictionary *progress = video ? self.videos[video] : nil;
    return [progress[@"done"] boolValue] ? 0 : [progress[@"position"] doubleValue];
}

- (double)progressOf:(NSString *)video {
    NSDictionary *progress = video ? self.videos[video] : nil;
    if ([progress[@"done"] boolValue]) return 1;
    double duration = [progress[@"duration"] doubleValue];
    return duration > 0 ? MIN(1, [progress[@"position"] doubleValue] / duration) : 0;
}

- (NSArray *)sortedItemsWhere:(BOOL (^)(ZLLibraryItem *item, NSDictionary *entry))test key:(NSString *)key {
    NSMutableArray *items = [NSMutableArray array];
    NSMutableArray *dates = [NSMutableArray array];
    for (NSDictionary *entry in self.titles.allValues) {
        ZLLibraryItem *item = [self itemFromEntry:entry];
        if (item && test(item, entry)) {
            [items addObject:item];
            [dates addObject:entry[key] ?: @0];
        }
    }
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSUInteger i = 0; i < items.count; i++) [pairs addObject:@[ dates[i], items[i] ]];
    [pairs sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [b[0] compare:a[0]]; }];
    NSMutableArray *sorted = [NSMutableArray array];
    for (NSArray *pair in pairs) [sorted addObject:pair[1]];
    return sorted;
}

- (NSArray *)continueWatching {
    return [self sortedItemsWhere:^BOOL(ZLLibraryItem *item, NSDictionary *entry) {
        if (!item.lastVideo || [entry[@"hidden"] boolValue]) return NO;
        if (![self isWatched:item.lastVideo]) return item.position > 30;
        // A finished episode stays when the series has a next episode.
        return [self nextEpisodeOf:item.meta] != nil;
    } key:@"watched"];
}

- (NSArray *)watchlist {
    return [self sortedItemsWhere:^BOOL(ZLLibraryItem *item, NSDictionary *entry) {
        return item.inWatchlist;
    } key:@"added"];
}

- (NSArray *)series {
    NSMutableArray *series = [NSMutableArray array];
    for (NSDictionary *entry in self.titles.allValues) {
        ZLLibraryItem *item = [self itemFromEntry:entry];
        if ([item.meta.type isEqualToString:@"series"]) [series addObject:item.meta];
    }
    return series;
}

- (ZLEpisode *)nextEpisodeOf:(ZLMeta *)meta {
    NSArray *episodes = meta.episodes;
    if (!episodes.count) return nil;
    // The extras of season 0 do not count.
    NSMutableArray *main = [NSMutableArray array];
    for (ZLEpisode *episode in episodes) {
        if (episode.season != 0) [main addObject:episode];
    }
    if (!main.count) main = [episodes mutableCopy];
    NSInteger last = -1;
    for (NSUInteger i = 0; i < main.count; i++) {
        ZLEpisode *episode = main[i];
        if ([self isWatched:episode.identifier]) last = (NSInteger)i;
        // An episode that did not finish comes first.
        else if ([self positionOf:episode.identifier] > 30) return episode;
    }
    for (NSUInteger i = (NSUInteger)(last + 1); i < main.count; i++) {
        ZLEpisode *episode = main[i];
        if ([self isWatched:episode.identifier]) continue;
        if (episode.released && [episode.released timeIntervalSinceNow] > 0) return nil;
        return episode;
    }
    return nil;
}

- (NSArray *)newEpisodesOf:(ZLMeta *)meta days:(NSInteger)days {
    NSMutableArray *found = [NSMutableArray array];
    NSDate *since = [NSDate dateWithTimeIntervalSinceNow:-days * 86400.0];
    for (ZLEpisode *episode in meta.episodes) {
        if (!episode.released || [episode.released timeIntervalSinceNow] > 0) continue;
        if ([episode.released compare:since] == NSOrderedAscending) continue;
        if (![self isWatched:episode.identifier]) [found addObject:episode];
    }
    return found;
}

- (NSDictionary *)backup {
    return [NSJSONSerialization JSONObjectWithData:[NSJSONSerialization dataWithJSONObject:self.data options:0 error:NULL]
                                           options:0 error:NULL];
}

- (BOOL)restore:(NSDictionary *)backup {
    if (![ZLJSONDictionary(backup, @"titles") isKindOfClass:[NSDictionary class]]) return NO;
    [self load:backup];
    [self save];
    return YES;
}

@end
