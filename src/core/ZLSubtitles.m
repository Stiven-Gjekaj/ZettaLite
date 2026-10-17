#import "ZLSubtitles.h"

@implementation ZLCue

+ (instancetype)cueWithStart:(double)start end:(double)end text:(NSString *)text {
    ZLCue *cue = [ZLCue new];
    cue.start = start;
    cue.end = end;
    cue.text = text;
    return cue;
}

@end

NSString *ZLSubtitleText(NSData *data) {
    if (!data.length) return nil;
    const uint8_t *bytes = data.bytes;
    if (data.length >= 2 && ((bytes[0] == 0xFF && bytes[1] == 0xFE) || (bytes[0] == 0xFE && bytes[1] == 0xFF))) {
        return [[NSString alloc] initWithData:data encoding:NSUnicodeStringEncoding];
    }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) text = [[NSString alloc] initWithData:data encoding:NSWindowsCP1252StringEncoding];
    if ([text hasPrefix:@"﻿"]) text = [text substringFromIndex:1];
    return text;
}

// Reads "01:02:03,456", "01:02:03.456", or "02:03.456". Returns -1 for other text.
static double ZLParseTime(NSString *text) {
    NSArray *parts = [[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
                      componentsSeparatedByString:@":"];
    if (parts.count < 2 || parts.count > 3) return -1;
    double seconds = 0;
    for (NSUInteger i = 0; i < parts.count; i++) {
        NSString *part = [parts[i] stringByReplacingOccurrencesOfString:@"," withString:@"."];
        NSScanner *scanner = [NSScanner scannerWithString:part];
        double value = 0;
        if (![scanner scanDouble:&value] || !scanner.isAtEnd || value < 0) return -1;
        seconds = seconds * 60 + value;
    }
    return seconds;
}

NSString *ZLCleanCueText(NSString *text) {
    NSMutableString *clean = [NSMutableString stringWithCapacity:text.length];
    NSUInteger length = text.length;
    for (NSUInteger i = 0; i < length; i++) {
        unichar character = [text characterAtIndex:i];
        if (character == '<' || character == '{') {
            unichar close = character == '<' ? '>' : '}';
            NSRange end = [text rangeOfString:[NSString stringWithCharacters:&close length:1]
                                      options:0 range:NSMakeRange(i, length - i)];
            if (end.location != NSNotFound) {
                i = end.location;
                continue;
            }
        }
        if (character == '\\' && i + 1 < length) {
            unichar next = [text characterAtIndex:i + 1];
            if (next == 'N' || next == 'n') {
                [clean appendString:@"\n"];
                i++;
                continue;
            }
            if (next == 'h') {
                [clean appendString:@" "];
                i++;
                continue;
            }
        }
        [clean appendFormat:@"%C", character];
    }
    NSString *result = [clean stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    result = [result stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
    result = [result stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
    result = [result stringByReplacingOccurrencesOfString:@"&nbsp;" withString:@" "];
    // Remove the empty lines that a removed tag leaves.
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *line in [result componentsSeparatedByString:@"\n"]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length) [lines addObject:trimmed];
    }
    return [lines componentsJoinedByString:@"\n"];
}

NSString *ZLASSPacketText(NSString *packet) {
    NSUInteger commas = 0;
    for (NSUInteger i = 0; i < packet.length; i++) {
        if ([packet characterAtIndex:i] == ',' && ++commas == 8) return ZLCleanCueText([packet substringFromIndex:i + 1]);
    }
    return ZLCleanCueText(packet);
}

NSArray *ZLParseSubtitles(NSString *text) {
    NSMutableArray *cues = [NSMutableArray array];
    NSString *normal = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
                        stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    NSArray *lines = [normal componentsSeparatedByString:@"\n"];
    NSUInteger i = 0;
    while (i < lines.count) {
        NSString *line = lines[i++];
        NSRange arrow = [line rangeOfString:@"-->"];
        if (arrow.location == NSNotFound) continue;
        double start = ZLParseTime([line substringToIndex:arrow.location]);
        // A WebVTT time line can have settings after the end time.
        NSString *rest = [[line substringFromIndex:arrow.location + 3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSRange space = [rest rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
        double end = ZLParseTime(space.location == NSNotFound ? rest : [rest substringToIndex:space.location]);
        NSMutableArray *body = [NSMutableArray array];
        while (i < lines.count && [lines[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length) {
            // A missing empty line before the next cue: stop at its time line.
            if ([lines[i] rangeOfString:@"-->"].location != NSNotFound) break;
            [body addObject:lines[i++]];
        }
        // An SRT number before the next time line is not text.
        if (body.count && i < lines.count && [lines[i] rangeOfString:@"-->"].location != NSNotFound) {
            NSString *last = body.lastObject;
            if ([last rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound) [body removeLastObject];
        }
        if (start < 0 || end <= start) continue;
        NSString *cueText = ZLCleanCueText([body componentsJoinedByString:@"\n"]);
        if (cueText.length) [cues addObject:[ZLCue cueWithStart:start end:end text:cueText]];
    }
    [cues sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(ZLCue *a, ZLCue *b) {
        return a.start < b.start ? NSOrderedAscending : a.start > b.start ? NSOrderedDescending : NSOrderedSame;
    }];
    return cues;
}

@interface ZLCueList ()
@property (nonatomic, strong) NSMutableArray *cues;
@end

@implementation ZLCueList

- (instancetype)init {
    return [self initWithCues:@[]];
}

- (instancetype)initWithCues:(NSArray *)cues {
    if ((self = [super init])) _cues = [cues mutableCopy] ?: [NSMutableArray array];
    return self;
}

// The index of the first cue that starts after the time.
static NSUInteger ZLFirstAfter(NSArray *cues, double seconds) {
    NSUInteger low = 0, high = cues.count;
    while (low < high) {
        NSUInteger middle = (low + high) / 2;
        if (((ZLCue *)cues[middle]).start <= seconds) low = middle + 1;
        else high = middle;
    }
    return low;
}

- (void)addCue:(ZLCue *)cue {
    @synchronized(self) {
        NSUInteger index = ZLFirstAfter(self.cues, cue.start);
        // A packet that comes again after a seek is already in the list.
        for (NSUInteger i = index; i > 0; i--) {
            ZLCue *other = self.cues[i - 1];
            if (other.start != cue.start) break;
            if ([other.text isEqualToString:cue.text]) return;
        }
        [self.cues insertObject:cue atIndex:index];
    }
}

- (NSUInteger)count {
    @synchronized(self) {
        return self.cues.count;
    }
}

- (NSString *)textAt:(double)seconds {
    @synchronized(self) {
        NSUInteger index = ZLFirstAfter(self.cues, seconds);
        NSMutableArray *texts = [NSMutableArray array];
        // Cues can overlap. Look back a small number of cues.
        for (NSUInteger i = index, looked = 0; i > 0 && looked < 16; i--, looked++) {
            ZLCue *cue = self.cues[i - 1];
            if (cue.end > seconds) [texts insertObject:cue.text atIndex:0];
        }
        return texts.count ? [texts componentsJoinedByString:@"\n"] : nil;
    }
}

@end
