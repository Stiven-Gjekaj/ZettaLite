// The rows that come from the library: Continue watching, New episodes, and
// the watchlist. Home and the Library tab show them.

#import <Foundation/Foundation.h>
#import "ZLMeta.h"

extern NSString *const ZLNewEpisodesDidChangeNotification;

@interface ZLLibraryRow : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSArray *metas;
@property (nonatomic, copy) NSArray *badges;     // NSString or NSNull
@property (nonatomic, copy) NSArray *progress;   // NSNumber
@property (nonatomic, copy) NSArray *episodes;   // ZLEpisode or NSNull: the episode that a tap plays
@end

@interface ZLLibraryRows : NSObject
+ (ZLLibraryRow *)continueWatching;
+ (ZLLibraryRow *)watchlist;
+ (ZLLibraryRow *)newEpisodes;
// Asks the addons for the series of the library again, to find new episodes.
// It runs at most one time in 6 hours.
+ (void)refreshNewEpisodes;
@end
