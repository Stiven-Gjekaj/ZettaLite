#import "ZLSources.h"
#import "ZLLink.h"
#import "ZLStore.h"

NSString *const ZLSourcesDidChangeNotification = @"ZLSourcesDidChange";

@implementation ZLSource
@end

static ZLSourceKind ZLKindOf(NSURL *url) {
    NSString *path = url.path.lowercaseString;
    if ([path hasSuffix:@"/manifest.json"] || [path isEqualToString:@"manifest.json"]) return ZLSourceAddon;
    if ([path hasSuffix:@".m3u"] || [path hasSuffix:@".m3u8"]) return ZLSourcePlaylist;
    if ([path hasSuffix:@".xml"] || [path hasSuffix:@".xml.gz"]) return ZLSourceGuide;
    // A playlist link of an IPTV service often has no extension.
    NSString *query = url.query.lowercaseString;
    if (query && [query rangeOfString:@"type=m3u"].location != NSNotFound) return ZLSourcePlaylist;
    return ZLSourceLink;
}

NSArray *ZLParseSources(NSString *text) {
    NSMutableArray *sources = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *raw in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!line.length || [line hasPrefix:@"#"]) continue;
        // The Stremio app shows addon links with stremio://. They are https.
        if ([line.lowercaseString hasPrefix:@"stremio://"]) line = [@"https://" stringByAppendingString:[line substringFromIndex:10]];
        NSURL *url = ZLMediaURLFromText(line);
        if (!url || [seen containsObject:url.absoluteString]) continue;
        [seen addObject:url.absoluteString];
        ZLSource *source = [ZLSource new];
        source.URL = url;
        source.kind = ZLKindOf(url);
        [sources addObject:source];
    }
    return sources;
}

@implementation ZLSourceList

+ (instancetype)shared {
    static ZLSourceList *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [ZLSourceList new]; });
    return shared;
}

- (NSString *)text {
    NSArray *lines = [[ZLStore shared] objectNamed:@"sources"];
    return [lines isKindOfClass:[NSArray class]] ? [lines componentsJoinedByString:@"\n"] : @"";
}

- (NSArray *)sources {
    return ZLParseSources([self text]);
}

- (NSArray *)sourcesOfKind:(ZLSourceKind)kind {
    NSMutableArray *matching = [NSMutableArray array];
    for (ZLSource *source in [self sources]) {
        if (source.kind == kind) [matching addObject:source];
    }
    return matching;
}

- (NSUInteger)setText:(NSString *)text {
    NSArray *sources = ZLParseSources(text);
    NSMutableArray *lines = [NSMutableArray array];
    for (ZLSource *source in sources) [lines addObject:source.URL.absoluteString];
    [[ZLStore shared] setObject:lines named:@"sources"];
    [[NSNotificationCenter defaultCenter] postNotificationName:ZLSourcesDidChangeNotification object:self];
    return sources.count;
}

@end
