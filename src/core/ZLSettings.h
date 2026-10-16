// The settings of the viewer. They stay in the user defaults.

#import <Foundation/Foundation.h>

extern NSString *const ZLSettingsDidChangeNotification;

@interface ZLSettings : NSObject
+ (instancetype)shared;
// Play starts the best stream at once. Otherwise Play shows the streams.
@property (nonatomic) BOOL autoplay;
// The stream picker also shows the streams that are too heavy for the phone.
@property (nonatomic) BOOL showHeavyStreams;
// The next episode starts after a countdown at the end of an episode.
@property (nonatomic) BOOL playNextEpisode;
// The audio language that the player picks first. ISO 639-2, or nil for the phone language.
@property (nonatomic, copy) NSString *audioLanguage;
// The subtitle language. ISO 639-2, or nil for no subtitles.
@property (nonatomic, copy) NSString *subtitleLanguage;
// The size of the subtitles in points.
@property (nonatomic) double subtitleSize;
// The audio languages in order: the setting, then the language of the phone.
- (NSArray *)audioLanguages;
@end

// The ISO 639-2 code of an ISO 639-1 code, for example "en" to "eng".
NSString *ZLLanguage3(NSString *code);
