// Reads an M3U playlist of live channels, as IPTV services give it:
//   #EXTM3U
//   #EXTINF:-1 tvg-id="news.1" tvg-logo="http://.../logo.png" group-title="News",News One
//   #EXTVLCOPT:http-user-agent=Player/1.0
//   #EXTVLCOPT:http-referrer=http://example.org/
//   http://example.org/live/news1.ts
// An HLS playlist (#EXT-X-TARGETDURATION or #EXT-X-STREAM-INF) is one stream,
// not a list of channels.

#import <Foundation/Foundation.h>

@interface ZLChannel : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSURL *URL;
@property (nonatomic, strong) NSURL *logo;
@property (nonatomic, copy) NSString *group;
@property (nonatomic, copy) NSString *tvgID;
@property (nonatomic, copy) NSDictionary *headers;
// A key that stays the same for the same channel: the URL.
- (NSString *)key;
@end

// YES when the text is an HLS playlist of one stream.
BOOL ZLIsHLSPlaylist(NSString *text);

// Returns the channels in the order of the playlist.
NSArray *ZLParseM3U(NSString *text, NSURL *base);
