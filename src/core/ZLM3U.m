#import "ZLM3U.h"

@implementation ZLChannel

- (NSString *)key {
    return self.URL.absoluteString;
}

@end

BOOL ZLIsHLSPlaylist(NSString *text) {
    return [text rangeOfString:@"#EXT-X-TARGETDURATION"].location != NSNotFound ||
           [text rangeOfString:@"#EXT-X-STREAM-INF"].location != NSNotFound ||
           [text rangeOfString:@"#EXT-X-MEDIA-SEQUENCE"].location != NSNotFound;
}

// Reads key="value" pairs of an #EXTINF line. The values can have spaces.
static NSDictionary *ZLAttributes(NSString *text) {
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    NSScanner *scanner = [NSScanner scannerWithString:text];
    scanner.charactersToBeSkipped = nil;
    while (!scanner.isAtEnd) {
        NSString *key = nil, *value = nil;
        [scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
        if (![scanner scanUpToString:@"=" intoString:&key]) break;
        if (![scanner scanString:@"=\"" intoString:NULL]) {
            // Not a quoted value: skip to the next space.
            [scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
            continue;
        }
        [scanner scanUpToString:@"\"" intoString:&value];
        [scanner scanString:@"\"" intoString:NULL];
        NSString *name = [[key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
        if (name.length) attributes[name] = value ?: @"";
    }
    return attributes;
}

// Finds the comma that starts the name: the first comma outside quotes.
static NSUInteger ZLNameComma(NSString *line) {
    BOOL quoted = NO;
    for (NSUInteger i = 0; i < line.length; i++) {
        unichar character = [line characterAtIndex:i];
        if (character == '"') quoted = !quoted;
        else if (character == ',' && !quoted) return i;
    }
    return NSNotFound;
}

NSArray *ZLParseM3U(NSString *text, NSURL *base) {
    NSMutableArray *channels = [NSMutableArray array];
    if (!text.length || ZLIsHLSPlaylist(text)) return channels;
    ZLChannel *pending = nil;
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    NSString *group = nil;
    for (NSString *raw in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!line.length) continue;
        if ([line hasPrefix:@"#EXTINF:"]) {
            pending = [ZLChannel new];
            headers = [NSMutableDictionary dictionary];
            NSUInteger comma = ZLNameComma(line);
            NSString *head = comma == NSNotFound ? line : [line substringToIndex:comma];
            NSString *name = comma == NSNotFound ? @"" : [line substringFromIndex:comma + 1];
            // The duration, then the attributes.
            NSRange space = [head rangeOfString:@" "];
            NSDictionary *attributes = space.location == NSNotFound ? @{} : ZLAttributes([head substringFromIndex:space.location]);
            pending.name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (!pending.name.length) pending.name = attributes[@"tvg-name"];
            pending.group = [attributes[@"group-title"] length] ? attributes[@"group-title"] : group;
            pending.tvgID = attributes[@"tvg-id"];
            NSString *logo = attributes[@"tvg-logo"];
            pending.logo = logo.length ? [NSURL URLWithString:logo] : nil;
            if (attributes[@"user-agent"]) headers[@"User-Agent"] = attributes[@"user-agent"];
            continue;
        }
        if ([line hasPrefix:@"#EXTGRP:"]) {
            group = [line substringFromIndex:8];
            if (pending && !pending.group.length) pending.group = group;
            continue;
        }
        if ([line hasPrefix:@"#EXTVLCOPT:"]) {
            NSString *option = [line substringFromIndex:11];
            NSRange equals = [option rangeOfString:@"="];
            if (equals.location == NSNotFound) continue;
            NSString *name = [option substringToIndex:equals.location].lowercaseString;
            NSString *value = [option substringFromIndex:equals.location + 1];
            if ([name isEqualToString:@"http-user-agent"]) headers[@"User-Agent"] = value;
            else if ([name isEqualToString:@"http-referrer"] || [name isEqualToString:@"http-referer"]) headers[@"Referer"] = value;
            else if ([name isEqualToString:@"http-origin"]) headers[@"Origin"] = value;
            continue;
        }
        if ([line hasPrefix:@"#EXTHTTP:"]) {
            NSData *json = [[line substringFromIndex:9] dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *values = [NSJSONSerialization JSONObjectWithData:json options:0 error:NULL];
            if ([values isKindOfClass:[NSDictionary class]]) {
                [values enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
                    if ([key isKindOfClass:[NSString class]] && [value isKindOfClass:[NSString class]]) headers[key] = value;
                }];
            }
            continue;
        }
        if ([line hasPrefix:@"#"]) continue;
        // A line with a link ends the entry. A link with "|" carries headers, as in Kodi.
        NSString *link = line;
        NSRange pipe = [line rangeOfString:@"|"];
        if (pipe.location != NSNotFound) {
            link = [line substringToIndex:pipe.location];
            for (NSString *pair in [[line substringFromIndex:pipe.location + 1] componentsSeparatedByString:@"&"]) {
                NSRange equals = [pair rangeOfString:@"="];
                if (equals.location == NSNotFound) continue;
                NSString *value = [[pair substringFromIndex:equals.location + 1] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
                if (value) headers[[pair substringToIndex:equals.location]] = value;
            }
        }
        NSURL *url = [NSURL URLWithString:link relativeToURL:base].absoluteURL;
        if (!url || !([url.scheme hasPrefix:@"http"])) {
            pending = nil;
            continue;
        }
        ZLChannel *channel = pending ?: [ZLChannel new];
        channel.URL = url;
        if (!channel.name.length) channel.name = url.lastPathComponent;
        channel.headers = headers.count ? [headers copy] : nil;
        [channels addObject:channel];
        pending = nil;
        headers = [NSMutableDictionary dictionary];
    }
    return channels;
}
