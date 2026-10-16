#import "ZLStreamInfo.h"
#import "ZLDecodeLimits.h"

// YES when the text has the word, with no letter or digit next to it.
static BOOL ZLHasWord(NSString *text, NSString *word) {
    NSString *pattern = [NSString stringWithFormat:@"(^|[^a-z0-9])%@($|[^a-z0-9])", word];
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                                options:NSRegularExpressionCaseInsensitive
                                                                                  error:NULL];
    return [expression firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] != nil;
}

static BOOL ZLHasAny(NSString *text, NSArray *words) {
    for (NSString *word in words) {
        if (ZLHasWord(text, word)) return YES;
    }
    return NO;
}

@implementation ZLStreamInfo

+ (instancetype)infoForText:(NSString *)text {
    ZLStreamInfo *info = [ZLStreamInfo new];
    NSString *value = text ?: @"";
    if (ZLHasAny(value, @[ @"2160p", @"4k", @"uhd" ])) info.height = 2160;
    else if (ZLHasAny(value, @[ @"1440p", @"2k" ])) info.height = 1440;
    else if (ZLHasAny(value, @[ @"1080p", @"1080i", @"fhd", @"fullhd" ])) info.height = 1080;
    else if (ZLHasAny(value, @[ @"720p", @"hd" ])) info.height = 720;
    else if (ZLHasAny(value, @[ @"576p", @"480p", @"sd", @"dvdrip", @"dvd" ])) info.height = 480;
    else if (ZLHasAny(value, @[ @"360p" ])) info.height = 360;

    info.dolbyVision = ZLHasAny(value, @[ @"dv", @"dovi", @"dolby ?vision" ]);
    info.hdr = info.dolbyVision || ZLHasAny(value, @[ @"hdr", @"hdr10", @"hdr10\\+", @"hlg" ]);
    info.tenBit = ZLHasAny(value, @[ @"10 ?bit", @"hi10p?", @"main10" ]) || info.hdr;

    if (ZLHasAny(value, @[ @"x265", @"h\\.?265", @"hevc" ])) info.codec = ZLVideoCodecHEVC;
    else if (ZLHasAny(value, @[ @"av1" ])) info.codec = ZLVideoCodecAV1;
    else if (ZLHasAny(value, @[ @"vp9" ])) info.codec = ZLVideoCodecVP9;
    else if (ZLHasAny(value, @[ @"x264", @"h\\.?264", @"avc" ])) info.codec = ZLVideoCodecH264;
    else if (ZLHasAny(value, @[ @"xvid", @"divx" ])) info.codec = ZLVideoCodecMPEG4;
    else if (ZLHasAny(value, @[ @"mpeg-?2" ])) info.codec = ZLVideoCodecMPEG2;

    NSArray *audio = @[ @[ @"atmos", @"Atmos" ], @[ @"truehd", @"TrueHD" ], @[ @"dts-?hd", @"DTS-HD" ], @[ @"dts", @"DTS" ],
                        @[ @"e-?ac-?3", @"E-AC3" ], @[ @"ddp|dd\\+", @"E-AC3" ], @[ @"ac-?3|dd|dolby ?digital", @"AC3" ],
                        @[ @"aac", @"AAC" ], @[ @"opus", @"Opus" ], @[ @"flac", @"FLAC" ], @[ @"mp3", @"MP3" ] ];
    for (NSArray *pair in audio) {
        // The channels can follow the codec, for example DD5.1 or AAC2.0.
        if (ZLHasWord(value, [NSString stringWithFormat:@"(%@)(?:[0-9]+(?:\\.[0-9]+)?)?", pair[0]])) {
            info.audio = pair[1];
            break;
        }
    }
    info.dualAudio = ZLHasAny(value, @[ @"dual ?audio", @"multi", @"dual" ]);
    info.camera = ZLHasAny(value, @[ @"cam", @"camrip", @"hdcam", @"ts", @"telesync", @"tc" ]);

    NSRegularExpression *size = [NSRegularExpression regularExpressionWithPattern:@"([0-9]+(?:[.,][0-9]+)?) ?(GB|MB|GiB|MiB)"
                                                                          options:NSRegularExpressionCaseInsensitive error:NULL];
    NSTextCheckingResult *match = [size firstMatchInString:value options:0 range:NSMakeRange(0, value.length)];
    if (match) {
        double amount = [[[value substringWithRange:[match rangeAtIndex:1]] stringByReplacingOccurrencesOfString:@"," withString:@"."] doubleValue];
        NSString *unit = [[value substringWithRange:[match rangeAtIndex:2]] uppercaseString];
        info.gigabytes = [unit hasPrefix:@"M"] ? amount / 1024 : amount;
    }
    return info;
}

- (BOOL)hardwareDecodes {
    // H.264 that the text does not call 10-bit, up to 1080p. A stream with no
    // codec in its text is most often H.264.
    BOOL h264 = self.codec == ZLVideoCodecH264 || self.codec == ZLVideoCodecUnknown;
    return h264 && !self.tenBit && self.height <= 1080;
}

- (NSString *)decoderName {
    switch (self.codec) {
        case ZLVideoCodecH264: return @"h264";
        case ZLVideoCodecHEVC: return @"hevc";
        case ZLVideoCodecAV1: return @"av1";
        case ZLVideoCodecVP9: return @"vp9";
        case ZLVideoCodecMPEG4: return @"mpeg4";
        case ZLVideoCodecMPEG2: return @"mpeg2video";
        default: return @"h264";
    }
}

- (BOOL)tooHeavy {
    if (self.height > 1080) return YES;
    if ([self hardwareDecodes]) return NO;
    // A size that the text does not say counts as 1080p.
    int height = self.height ?: 1080;
    int width = height * 16 / 9;
    return !ZLSoftwareDecodeFits([self decoderName], self.tenBit ? 10 : 8, width, height, 24);
}

- (NSString *)qualityText {
    if (self.height >= 2160) return @"4K";
    if (self.height > 0) return [NSString stringWithFormat:@"%dp", self.height];
    return nil;
}

- (NSArray *)badges {
    NSMutableArray *badges = [NSMutableArray array];
    if ([self qualityText]) [badges addObject:[self qualityText]];
    if (self.dolbyVision) [badges addObject:@"DV"];
    else if (self.hdr) [badges addObject:@"HDR"];
    if (self.codec == ZLVideoCodecHEVC) [badges addObject:@"HEVC"];
    if (self.codec == ZLVideoCodecAV1) [badges addObject:@"AV1"];
    if (self.codec == ZLVideoCodecVP9) [badges addObject:@"VP9"];
    if (self.tenBit && !self.hdr) [badges addObject:@"10-bit"];
    if (self.audio) [badges addObject:self.audio];
    if (self.dualAudio) [badges addObject:@"Dual audio"];
    if (self.gigabytes > 0) [badges addObject:[NSString stringWithFormat:@"%.1f GB", self.gigabytes]];
    if ([self tooHeavy]) [badges addObject:@"Too heavy"];
    else if (![self hardwareDecodes]) [badges addObject:@"Software"];
    return badges;
}

- (double)score {
    if ([self tooHeavy]) return 0;
    double score = 10;
    // 1080p in hardware is best. In software, a smaller picture plays better.
    if ([self hardwareDecodes]) score += 100 + (self.height ?: 720) / 10.0;
    else score += 40 + (self.height ?: 480) / 40.0;
    if (self.camera) score -= 60;
    // A very large file needs a fast network.
    if (self.gigabytes > 8) score -= 10;
    return MAX(score, 1);
}

@end
