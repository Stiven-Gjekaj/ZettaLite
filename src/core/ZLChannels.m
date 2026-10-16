#import "ZLChannels.h"
#import "ZLHTTPStream.h"
#import "ZLLog.h"
#import "ZLSources.h"
#import "ZLStore.h"

NSString *const ZLChannelsDidChangeNotification = @"ZLChannelsDidChange";

// The name of a group for channels with no group.
static NSString *const ZLOtherGroup = @"Other";

static NSString *ZLPlaylistText(NSData *data) {
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    // Old playlists can be in Latin-1.
    return text ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
}

static ZLChannel *ZLChannelForLink(NSURL *url) {
    ZLChannel *channel = [ZLChannel new];
    channel.URL = url;
    NSString *name = url.lastPathComponent.stringByDeletingPathExtension;
    // A name such as "index" or "playlist" says nothing. Use the host then.
    if (!name.length || [@[ @"index", @"playlist", @"master", @"live", @"stream", @"chunklist" ] containsObject:name.lowercaseString]) name = url.host;
    channel.name = name;
    channel.group = @"Links";
    return channel;
}

NSArray *ZLFetchChannels(NSURL *url, NSError **error) {
    NSString *path = url.path.lowercaseString;
    BOOL playlist = [path hasSuffix:@".m3u"] || [path hasSuffix:@".m3u8"] ||
                    (url.query && [url.query.lowercaseString rangeOfString:@"type=m3u"].location != NSNotFound);
    // Any other link is a media file or a stream. Do not fetch it.
    if (!playlist) return @[ ZLChannelForLink(url) ];
    NSURL *finalURL = nil;
    NSData *data = [ZLHTTPStream fetch:url headers:nil finalURL:&finalURL error:error];
    if (!data) return nil;
    NSString *text = ZLPlaylistText(data);
    if (ZLIsHLSPlaylist(text)) return @[ ZLChannelForLink(url) ];
    return ZLParseM3U(text, finalURL ?: url);
}

@interface ZLChannelList ()
@property (nonatomic, strong) ZLStore *store;
@property (nonatomic, readwrite) BOOL loading;
@property (nonatomic, readwrite) NSArray *channels;
@property (nonatomic, readwrite) NSArray *failures;
@property (nonatomic) NSUInteger generation;
@end

@implementation ZLChannelList

+ (instancetype)shared {
    static ZLChannelList *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[ZLChannelList alloc] initWithStore:[ZLStore shared]];
        [[NSNotificationCenter defaultCenter] addObserver:shared selector:@selector(reload)
                                                     name:ZLSourcesDidChangeNotification object:nil];
    });
    return shared;
}

- (instancetype)initWithStore:(id)store {
    if ((self = [super init])) {
        _store = store;
        _channels = @[];
        _failures = @[];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reload {
    NSUInteger generation = ++self.generation;
    NSMutableArray *urls = [NSMutableArray array];
    for (ZLSource *source in [[ZLSourceList shared] sources]) {
        if (source.kind == ZLSourcePlaylist || source.kind == ZLSourceLink) [urls addObject:source.URL];
    }
    self.loading = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:ZLChannelsDidChangeNotification object:self];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray *channels = [NSMutableArray array];
        NSMutableArray *failures = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet set];
        for (NSURL *url in urls) {
            NSError *error = nil;
            NSArray *found = ZLFetchChannels(url, &error);
            if (!found) {
                ZLLog(@"playlist %@: %@", url, error.localizedDescription);
                [failures addObject:[NSString stringWithFormat:@"%@: %@", url.absoluteString, error.localizedDescription ?: @"The playlist did not load."]];
                continue;
            }
            for (ZLChannel *channel in found) {
                if ([seen containsObject:channel.key]) continue;
                [seen addObject:channel.key];
                [channels addObject:channel];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.generation) return;
            self.loading = NO;
            [self setChannels:channels failures:failures];
        });
    });
}

- (void)setChannels:(NSArray *)channels failures:(NSArray *)failures {
    self.channels = [channels copy] ?: @[];
    self.failures = [failures copy] ?: @[];
    [[NSNotificationCenter defaultCenter] postNotificationName:ZLChannelsDidChangeNotification object:self];
}

static NSString *ZLGroupOf(ZLChannel *channel) {
    return channel.group.length ? channel.group : ZLOtherGroup;
}

- (NSArray *)groups {
    NSMutableArray *groups = [NSMutableArray array];
    BOOL other = NO;
    for (ZLChannel *channel in self.channels) {
        NSString *group = ZLGroupOf(channel);
        if (!channel.group.length) other = YES;
        else if (![groups containsObject:group]) [groups addObject:group];
    }
    // The channels with no group come last.
    if (other && ![groups containsObject:ZLOtherGroup]) [groups addObject:ZLOtherGroup];
    return groups;
}

- (NSArray *)channelsInGroup:(NSString *)group {
    NSMutableArray *channels = [NSMutableArray array];
    for (ZLChannel *channel in self.channels) {
        if ([ZLGroupOf(channel) isEqualToString:group]) [channels addObject:channel];
    }
    return channels;
}

- (NSArray *)favouriteKeys {
    NSArray *keys = [self.store objectNamed:@"favourites"];
    return [keys isKindOfClass:[NSArray class]] ? keys : @[];
}

- (BOOL)isFavourite:(ZLChannel *)channel {
    return channel.key && [[self favouriteKeys] containsObject:channel.key];
}

- (void)setChannel:(ZLChannel *)channel favourite:(BOOL)favourite {
    if (!channel.key) return;
    NSMutableArray *keys = [[self favouriteKeys] mutableCopy];
    [keys removeObject:channel.key];
    if (favourite) [keys addObject:channel.key];
    [self.store setObject:keys named:@"favourites"];
    [[NSNotificationCenter defaultCenter] postNotificationName:ZLChannelsDidChangeNotification object:self];
}

- (NSArray *)favourites {
    NSSet *keys = [NSSet setWithArray:[self favouriteKeys]];
    NSMutableArray *favourites = [NSMutableArray array];
    for (ZLChannel *channel in self.channels) {
        if ([keys containsObject:channel.key]) [favourites addObject:channel];
    }
    return favourites;
}

@end
