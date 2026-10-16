// The channels of the Live TV tab. They come from the M3U playlists and the
// media links in Sources. A .m3u8 link can be a list of channels or one HLS
// stream. The list fetches it and looks at the text to know which.
// The favourites stay in the store as "favourites", by the URL of the channel.

#import <Foundation/Foundation.h>
#import "ZLM3U.h"

extern NSString *const ZLChannelsDidChangeNotification;

// Fetches one source and returns its channels. It blocks. A link that is not
// a playlist becomes one channel.
NSArray *ZLFetchChannels(NSURL *url, NSError **error);

@interface ZLChannelList : NSObject

+ (instancetype)shared;
// Tests give their own store.
- (instancetype)initWithStore:(id)store;

@property (nonatomic, readonly) BOOL loading;
// All the channels, in the order of Sources and then of each playlist.
@property (nonatomic, readonly) NSArray *channels;
// The sources that failed, as "URL: reason".
@property (nonatomic, readonly) NSArray *failures;

// Fetches the playlists and the links of Sources again.
- (void)reload;
// Sets the channels without a fetch.
- (void)setChannels:(NSArray *)channels failures:(NSArray *)failures;

// The names of the groups in the order that they first come.
- (NSArray *)groups;
- (NSArray *)channelsInGroup:(NSString *)group;

- (BOOL)isFavourite:(ZLChannel *)channel;
- (void)setChannel:(ZLChannel *)channel favourite:(BOOL)favourite;
// The favourite channels in the order of the list.
- (NSArray *)favourites;

@end
