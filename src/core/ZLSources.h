// The list of sources, as in ZettaStream: one URL on each line. A line can be
// a Stremio addon, an M3U playlist, or a media link. A new list replaces the
// old list. The order of the lines is the order of the rows on Home.

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, ZLSourceKind) {
    ZLSourceAddon,     // .../manifest.json
    ZLSourcePlaylist,  // .m3u or .m3u8
    ZLSourceGuide,     // .xml or .xml.gz. The app has no TV guide, so it ignores it.
    ZLSourceLink,      // Any other http or https link.
};

extern NSString *const ZLSourcesDidChangeNotification;

@interface ZLSource : NSObject
@property (nonatomic, strong) NSURL *URL;
@property (nonatomic) ZLSourceKind kind;
@end

// Reads a pasted list. It ignores empty lines, lines that start with "#",
// lines that are not links, and lines that come again.
NSArray *ZLParseSources(NSString *text);

@class ZLStore;

@interface ZLSourceList : NSObject
+ (instancetype)shared;
// Tests give their own store.
- (instancetype)initWithStore:(ZLStore *)store;
- (NSArray *)sources;
- (NSArray *)sourcesOfKind:(ZLSourceKind)kind;
// The list as text, one URL on each line.
- (NSString *)text;
// Replaces the list. Returns the number of sources.
- (NSUInteger)setText:(NSString *)text;
@end
