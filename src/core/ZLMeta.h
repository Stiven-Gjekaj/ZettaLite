// The titles, the episodes, and the streams that addons give.

#import <Foundation/Foundation.h>

@class ZLAddon;

// One episode of a series, or one part of a title.
@interface ZLEpisode : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic) NSInteger season;
@property (nonatomic) NSInteger episode;
@property (nonatomic, copy) NSString *overview;
@property (nonatomic, strong) NSURL *thumbnail;
@property (nonatomic, strong) NSDate *released;
+ (instancetype)episodeWithJSON:(NSDictionary *)json;
// For example "S1 E2".
- (NSString *)code;
@end

// A title: a film, a series, a channel, or another type of an addon.
@interface ZLMeta : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSURL *poster;
@property (nonatomic, copy) NSString *posterShape;  // "poster", "landscape", or "square"
@property (nonatomic, strong) NSURL *background;
@property (nonatomic, strong) NSURL *logo;
@property (nonatomic, copy) NSString *summary;
@property (nonatomic, copy) NSString *releaseInfo;  // For example "2008" or "2011-2019".
@property (nonatomic, copy) NSString *rating;  // The IMDb rating, for example "8.4".
@property (nonatomic, copy) NSString *runtime;
@property (nonatomic, copy) NSArray *genres;
@property (nonatomic, copy) NSArray *cast;
@property (nonatomic, copy) NSArray *directors;
@property (nonatomic, copy) NSArray *episodes;  // ZLEpisode, in order.
// The addon that gave the title. Its meta resource gives the full title.
@property (nonatomic, weak) ZLAddon *addon;
// The JSON of the title, so that the library can keep it.
@property (nonatomic, copy) NSDictionary *json;

+ (instancetype)metaWithJSON:(NSDictionary *)json;
// The seasons in order. Season 0 (the extras) comes last.
- (NSArray *)seasons;
- (NSArray *)episodesOfSeason:(NSInteger)season;
// For example "2008 · 1h 36m · 8.4". It has no separator character that
// iOS 6 cannot show.
- (NSString *)facts;
@end

// One stream that an addon gives for a title.
@interface ZLStream : NSObject
@property (nonatomic, strong) NSURL *URL;  // nil for a torrent or an external link.
@property (nonatomic, copy) NSString *infoHash;
@property (nonatomic, strong) NSURL *externalURL;
@property (nonatomic, copy) NSString *name;  // The first line, often the addon and the quality.
@property (nonatomic, copy) NSString *title;  // The other lines.
@property (nonatomic, copy) NSDictionary *headers;  // From behaviorHints.proxyHeaders.request
@property (nonatomic, copy) NSString *bingeGroup;
@property (nonatomic, copy) NSString *filename;
@property (nonatomic) long long size;
@property (nonatomic, copy) NSArray *subtitles;  // Dictionaries with url and lang.
@property (nonatomic, weak) ZLAddon *addon;
@property (nonatomic, copy) NSString *addonName;
+ (instancetype)streamWithJSON:(NSDictionary *)json;
- (BOOL)isTorrent;
// All the text of the stream, for the search of quality words.
- (NSString *)allText;
@end
