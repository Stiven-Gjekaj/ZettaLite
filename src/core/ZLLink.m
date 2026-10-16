#import "ZLLink.h"

@implementation ZLLink
@end

static NSDictionary *ZLQuery(NSURL *url) {
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSString *pair in [url.query componentsSeparatedByString:@"&"]) {
        NSRange equals = [pair rangeOfString:@"="];
        if (equals.location == NSNotFound) continue;
        NSString *key = [pair substringToIndex:equals.location];
        NSString *value = [[pair substringFromIndex:equals.location + 1] stringByReplacingOccurrencesOfString:@"+" withString:@" "];
        value = [value stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        if (key.length && value) values[key] = value;
    }
    return values;
}

NSURL *ZLMediaURLFromText(NSString *text) {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSURL *url = [NSURL URLWithString:trimmed];
    if (!url) {
        // A URL with spaces or other characters that NSURL refuses.
        url = [NSURL URLWithString:[trimmed stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    }
    NSString *scheme = url.scheme.lowercaseString;
    if (!([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) || !url.host.length) return nil;
    return url;
}

ZLLink *ZLParseLink(NSURL *url) {
    if (![url.scheme.lowercaseString isEqualToString:@"zettalite"]) return nil;
    NSString *host = url.host.lowercaseString;
    NSDictionary *query = ZLQuery(url);
    ZLLink *link = [ZLLink new];
    if ([host isEqualToString:@"play"]) {
        NSURL *media = ZLMediaURLFromText(query[@"url"]);
        if (!media) return nil;
        link.kind = ZLLinkPlay;
        link.mediaURL = media;
        link.title = query[@"title"];
        link.startTime = MAX(0, [query[@"t"] doubleValue]);
    } else if ([host isEqualToString:@"title"]) {
        if (![query[@"type"] length] || ![query[@"id"] length]) return nil;
        link.kind = ZLLinkTitle;
        link.type = query[@"type"];
        link.identifier = query[@"id"];
    } else if ([host isEqualToString:@"search"]) {
        if (![query[@"q"] length]) return nil;
        link.kind = ZLLinkSearch;
        link.text = query[@"q"];
    } else if ([host isEqualToString:@"tab"]) {
        NSArray *tabs = @[ @"home", @"search", @"library", @"live", @"settings" ];
        if (![tabs containsObject:query[@"name"]]) return nil;
        link.kind = ZLLinkTab;
        link.text = query[@"name"];
    } else {
        return nil;
    }
    return link;
}
