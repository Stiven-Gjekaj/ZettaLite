#import "ZLMeta.h"
#import "ZLJSON.h"

static NSURL *ZLJSONURL(id dictionary, NSString *key) {
    NSString *text = ZLJSONString(dictionary, key);
    if (!text) return nil;
    NSURL *url = [NSURL URLWithString:text];
    if (!url) url = [NSURL URLWithString:[text stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    return [url.scheme hasPrefix:@"http"] ? url : nil;
}

static NSDate *ZLJSONDate(id dictionary, NSString *key) {
    NSString *text = ZLJSONString(dictionary, key);
    if (text.length < 10) return nil;
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [NSDateFormatter new];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
        formatter.dateFormat = @"yyyy-MM-dd";
    });
    @synchronized (formatter) {
        return [formatter dateFromString:[text substringToIndex:10]];
    }
}

// Names from an array of strings, or of objects with a name.
static NSArray *ZLJSONNames(id dictionary, NSString *key) {
    NSMutableArray *names = [NSMutableArray array];
    for (id item in ZLJSONArray(dictionary, key)) {
        if ([item isKindOfClass:[NSString class]] && [item length]) [names addObject:item];
        else if (ZLJSONString(item, @"name")) [names addObject:ZLJSONString(item, @"name")];
    }
    return names;
}

@implementation ZLEpisode

+ (instancetype)episodeWithJSON:(NSDictionary *)json {
    NSString *identifier = ZLJSONString(json, @"id");
    if (!identifier) return nil;
    ZLEpisode *episode = [ZLEpisode new];
    episode.identifier = identifier;
    episode.title = ZLJSONString(json, @"title") ?: ZLJSONString(json, @"name");
    episode.season = ZLJSONInteger(json, @"season", 0);
    episode.episode = ZLJSONInteger(json, @"episode", ZLJSONInteger(json, @"number", 0));
    episode.overview = ZLJSONString(json, @"overview") ?: ZLJSONString(json, @"description");
    episode.thumbnail = ZLJSONURL(json, @"thumbnail");
    episode.released = ZLJSONDate(json, @"released") ?: ZLJSONDate(json, @"firstAired");
    return episode;
}

- (NSString *)code {
    if (self.episode <= 0) return self.title ?: @"";
    return [NSString stringWithFormat:@"S%ld E%ld", (long)self.season, (long)self.episode];
}

@end

@implementation ZLMeta

+ (instancetype)metaWithJSON:(NSDictionary *)json {
    NSString *identifier = ZLJSONString(json, @"id");
    NSString *type = ZLJSONString(json, @"type");
    if (!identifier || !type) return nil;
    ZLMeta *meta = [ZLMeta new];
    meta.json = json;
    meta.identifier = identifier;
    meta.type = type;
    meta.name = ZLJSONString(json, @"name") ?: identifier;
    meta.poster = ZLJSONURL(json, @"poster");
    meta.posterShape = ZLJSONString(json, @"posterShape") ?: @"poster";
    meta.background = ZLJSONURL(json, @"background");
    meta.logo = ZLJSONURL(json, @"logo");
    meta.summary = ZLJSONString(json, @"description");
    meta.releaseInfo = ZLJSONString(json, @"releaseInfo") ?: ZLJSONString(json, @"year");
    meta.rating = ZLJSONString(json, @"imdbRating");
    meta.runtime = ZLJSONString(json, @"runtime");
    meta.genres = ZLJSONArray(json, @"genres") ? ZLJSONStrings(json, @"genres") : ZLJSONStrings(json, @"genre");
    meta.cast = ZLJSONNames(json, @"cast");
    meta.directors = ZLJSONNames(json, @"director");
    // Newer addons give the cast and the genres as links.
    NSMutableArray *cast = [meta.cast mutableCopy];
    NSMutableArray *genres = [meta.genres mutableCopy];
    for (NSDictionary *link in ZLJSONArray(json, @"links")) {
        NSString *category = ZLJSONString(link, @"category");
        NSString *name = ZLJSONString(link, @"name");
        if (!name) continue;
        if ([category isEqualToString:@"Cast"] && ![cast containsObject:name]) [cast addObject:name];
        if ([category isEqualToString:@"Genres"] && ![genres containsObject:name]) [genres addObject:name];
    }
    meta.cast = cast;
    meta.genres = genres;
    NSMutableArray *episodes = [NSMutableArray array];
    for (NSDictionary *item in ZLJSONArray(json, @"videos")) {
        ZLEpisode *episode = [ZLEpisode episodeWithJSON:item];
        if (episode) [episodes addObject:episode];
    }
    [episodes sortUsingComparator:^NSComparisonResult(ZLEpisode *a, ZLEpisode *b) {
        if (a.season != b.season) return a.season < b.season ? NSOrderedAscending : NSOrderedDescending;
        if (a.episode != b.episode) return a.episode < b.episode ? NSOrderedAscending : NSOrderedDescending;
        return NSOrderedSame;
    }];
    meta.episodes = episodes;
    return meta;
}

- (NSArray *)seasons {
    NSMutableOrderedSet *seasons = [NSMutableOrderedSet orderedSet];
    for (ZLEpisode *episode in self.episodes) [seasons addObject:@(episode.season)];
    NSMutableArray *sorted = [[seasons array] mutableCopy];
    [sorted sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        // Season 0 holds the extras. It goes last.
        if (a.integerValue == 0) return NSOrderedDescending;
        if (b.integerValue == 0) return NSOrderedAscending;
        return [a compare:b];
    }];
    return sorted;
}

- (NSArray *)episodesOfSeason:(NSInteger)season {
    NSMutableArray *episodes = [NSMutableArray array];
    for (ZLEpisode *episode in self.episodes) {
        if (episode.season == season) [episodes addObject:episode];
    }
    return episodes;
}

- (NSString *)facts {
    NSMutableArray *parts = [NSMutableArray array];
    if (self.releaseInfo.length) [parts addObject:self.releaseInfo];
    if (self.runtime.length) [parts addObject:self.runtime];
    if (self.rating.length) [parts addObject:[NSString stringWithFormat:@"IMDb %@", self.rating]];
    return [parts componentsJoinedByString:@"  |  "];
}

@end

@implementation ZLStream

+ (instancetype)streamWithJSON:(NSDictionary *)json {
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    ZLStream *stream = [ZLStream new];
    stream.URL = ZLJSONURL(json, @"url");
    stream.infoHash = ZLJSONString(json, @"infoHash");
    stream.externalURL = ZLJSONURL(json, @"externalUrl");
    if (!stream.URL && !stream.infoHash && !stream.externalURL) return nil;
    stream.name = ZLJSONString(json, @"name");
    stream.title = ZLJSONString(json, @"title") ?: ZLJSONString(json, @"description");
    NSDictionary *hints = ZLJSONDictionary(json, @"behaviorHints");
    NSDictionary *request = ZLJSONDictionary(ZLJSONDictionary(hints, @"proxyHeaders"), @"request");
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    [request enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        if ([key isKindOfClass:[NSString class]] && [value isKindOfClass:[NSString class]]) headers[key] = value;
    }];
    stream.headers = headers.count ? headers : nil;
    stream.bingeGroup = ZLJSONString(hints, @"bingeGroup");
    stream.filename = ZLJSONString(hints, @"filename");
    stream.size = [ZLJSONNumber(hints, @"videoSize") longLongValue];
    NSMutableArray *subtitles = [NSMutableArray array];
    for (NSDictionary *item in ZLJSONArray(json, @"subtitles")) {
        if (ZLJSONString(item, @"url")) [subtitles addObject:item];
    }
    stream.subtitles = subtitles;
    return stream;
}

- (BOOL)isTorrent {
    return !self.URL && self.infoHash.length;
}

- (NSString *)allText {
    NSMutableArray *parts = [NSMutableArray array];
    if (self.name) [parts addObject:self.name];
    if (self.title) [parts addObject:self.title];
    if (self.filename) [parts addObject:self.filename];
    return [parts componentsJoinedByString:@"\n"];
}

@end
