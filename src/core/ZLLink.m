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
    if (![url.host.lowercaseString isEqualToString:@"play"]) return nil;
    NSDictionary *query = ZLQuery(url);
    NSURL *media = ZLMediaURLFromText(query[@"url"]);
    if (!media) return nil;
    ZLLink *link = [ZLLink new];
    link.mediaURL = media;
    link.title = query[@"title"];
    return link;
}
