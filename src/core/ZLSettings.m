#import "ZLSettings.h"

NSString *const ZLSettingsDidChangeNotification = @"ZLSettingsDidChange";

NSString *ZLLanguage3(NSString *code) {
    if (code.length == 3) return code.lowercaseString;
    if (code.length < 2) return nil;
    NSDictionary *map = @{ @"en": @"eng", @"de": @"ger", @"fr": @"fre", @"es": @"spa", @"it": @"ita", @"pt": @"por",
                           @"ja": @"jpn", @"sq": @"alb", @"ru": @"rus", @"nl": @"dut", @"pl": @"pol", @"tr": @"tur",
                           @"ar": @"ara", @"zh": @"chi", @"ko": @"kor", @"sv": @"swe", @"no": @"nor", @"da": @"dan",
                           @"fi": @"fin", @"el": @"gre", @"he": @"heb", @"hu": @"hun", @"cs": @"cze", @"ro": @"rum",
                           @"sr": @"srp", @"hr": @"hrv", @"bg": @"bul", @"uk": @"ukr", @"hi": @"hin", @"th": @"tha",
                           @"vi": @"vie", @"id": @"ind", @"ms": @"may", @"fa": @"per" };
    return map[[code substringToIndex:2].lowercaseString];
}

@implementation ZLSettings

+ (instancetype)shared {
    static ZLSettings *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [ZLSettings new];
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{
            @"ZLAutoplay": @YES, @"ZLShowHeavy": @NO, @"ZLPlayNext": @YES, @"ZLSubtitleSize": @18,
        }];
    });
    return shared;
}

- (NSUserDefaults *)defaults {
    return [NSUserDefaults standardUserDefaults];
}

- (void)changed {
    [[NSNotificationCenter defaultCenter] postNotificationName:ZLSettingsDidChangeNotification object:self];
}

- (BOOL)autoplay { return [self.defaults boolForKey:@"ZLAutoplay"]; }
- (void)setAutoplay:(BOOL)value { [self.defaults setBool:value forKey:@"ZLAutoplay"]; [self changed]; }
- (BOOL)showHeavyStreams { return [self.defaults boolForKey:@"ZLShowHeavy"]; }
- (void)setShowHeavyStreams:(BOOL)value { [self.defaults setBool:value forKey:@"ZLShowHeavy"]; [self changed]; }
- (BOOL)playNextEpisode { return [self.defaults boolForKey:@"ZLPlayNext"]; }
- (void)setPlayNextEpisode:(BOOL)value { [self.defaults setBool:value forKey:@"ZLPlayNext"]; [self changed]; }
- (NSString *)audioLanguage { return [self.defaults stringForKey:@"ZLAudioLanguage"]; }
- (void)setAudioLanguage:(NSString *)value { [self.defaults setObject:value forKey:@"ZLAudioLanguage"]; [self changed]; }
- (NSString *)subtitleLanguage { return [self.defaults stringForKey:@"ZLSubtitleLanguage"]; }
- (void)setSubtitleLanguage:(NSString *)value { [self.defaults setObject:value forKey:@"ZLSubtitleLanguage"]; [self changed]; }
- (double)subtitleSize { return [self.defaults doubleForKey:@"ZLSubtitleSize"]; }
- (void)setSubtitleSize:(double)value { [self.defaults setDouble:value forKey:@"ZLSubtitleSize"]; [self changed]; }

- (NSArray *)audioLanguages {
    NSMutableArray *languages = [NSMutableArray array];
    if (self.audioLanguage.length) [languages addObject:self.audioLanguage];
    NSString *phone = ZLLanguage3([[NSLocale preferredLanguages] firstObject]);
    if (phone && ![languages containsObject:phone]) [languages addObject:phone];
    return languages;
}

@end
