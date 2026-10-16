// The library on the phone: the watchlist, the progress of each film and
// episode, and the watched marks. It stays in the store as "library".

#import <Foundation/Foundation.h>
#import "ZLMeta.h"

extern NSString *const ZLLibraryDidChangeNotification;

// A film or an episode counts as watched after this part of it.
extern const double ZLWatchedPart;

@interface ZLLibraryItem : NSObject
@property (nonatomic, strong) ZLMeta *meta;  // The title, as the library keeps it.
@property (nonatomic) BOOL inWatchlist;
@property (nonatomic, strong) NSDate *lastWatched;
// The film or the episode that played last, and where it stopped.
@property (nonatomic, copy) NSString *lastVideo;
@property (nonatomic) double position;
@property (nonatomic) double duration;
// The part of the last video that played, from 0 to 1.
- (double)progress;
@end

@interface ZLLibrary : NSObject

+ (instancetype)shared;
// Tests give their own store name, so that they do not change the real library.
- (instancetype)initWithStoreName:(NSString *)name store:(id)store;

- (ZLLibraryItem *)itemFor:(NSString *)identifier;
- (BOOL)isInWatchlist:(NSString *)identifier;
- (void)setMeta:(ZLMeta *)meta inWatchlist:(BOOL)inWatchlist;
// Keeps a newer copy of a title that is in the library already.
- (void)updateMeta:(ZLMeta *)meta;

// video is the ID of the episode, or the ID of the film.
- (void)recordMeta:(ZLMeta *)meta video:(NSString *)video position:(double)position duration:(double)duration;
- (BOOL)isWatched:(NSString *)video;
- (void)setVideo:(NSString *)video ofMeta:(ZLMeta *)meta watched:(BOOL)watched;
// The second where a film or an episode stopped, or 0.
- (double)positionOf:(NSString *)video;
- (double)progressOf:(NSString *)video;

// The titles with a film or an episode that did not finish, or with a next
// episode, newest first.
- (NSArray *)continueWatching;
// The titles of the watchlist, newest first.
- (NSArray *)watchlist;
// The series of the library, for the check of new episodes.
- (NSArray *)series;

// The episode to play next: the one that did not finish, else the first
// episode after the last watched one that is out. nil when all are watched.
- (ZLEpisode *)nextEpisodeOf:(ZLMeta *)meta;
// The episodes that came out in the last days and that are not watched.
- (NSArray *)newEpisodesOf:(ZLMeta *)meta days:(NSInteger)days;

// The library as JSON, for a backup, and back.
- (NSDictionary *)backup;
- (BOOL)restore:(NSDictionary *)backup;

@end
