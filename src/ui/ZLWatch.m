#import "ZLWatch.h"
#import <QuartzCore/QuartzCore.h>
#import "ZLAddonManager.h"
#import "ZLLibrary.h"
#import "ZLLog.h"
#import "ZLPlayback.h"
#import "ZLSettings.h"
#import "ZLStreamRank.h"
#import "ZLStreamsViewController.h"
#import "ZLTheme.h"

// The seconds of the countdown to the next episode.
static const int ZLCountdownSeconds = 10;

#pragma mark - Countdown

// A box at the bottom of the window: "Next: S1 E3 in 10 s", with Play now and Cancel.
@interface ZLCountdownView : UIView
@property (nonatomic, strong) UILabel *label;
@property (nonatomic) int left;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) void (^onPlay)(void);
@end

@implementation ZLCountdownView

+ (void)showIn:(UIView *)window name:(NSString *)name onPlay:(void (^)(void))onPlay {
    CGFloat width = window.bounds.size.width;
    ZLCountdownView *view = [[ZLCountdownView alloc] initWithFrame:CGRectMake(10, window.bounds.size.height - 160, width - 20, 96)];
    view.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.95];
    view.layer.cornerRadius = 10;
    view.layer.borderWidth = 1;
    view.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.15].CGColor;
    view.name = name;
    view.onPlay = onPlay;
    view.left = ZLCountdownSeconds;
    view.label = [[UILabel alloc] initWithFrame:CGRectMake(12, 10, width - 44, 34)];
    view.label.font = ZLBoldFont(15);
    view.label.textColor = ZLTextColor();
    view.label.backgroundColor = [UIColor clearColor];
    view.label.numberOfLines = 2;
    [view addSubview:view.label];
    UIButton *play = [UIButton buttonWithType:UIButtonTypeCustom];
    play.frame = CGRectMake(12, 50, (width - 44) / 2, 36);
    play.backgroundColor = ZLAccentColor();
    play.layer.cornerRadius = 6;
    play.titleLabel.font = ZLBoldFont(15);
    [play setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [play setTitle:@"Play now" forState:UIControlStateNormal];
    [play addTarget:view action:@selector(playNow) forControlEvents:UIControlEventTouchUpInside];
    [view addSubview:play];
    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeCustom];
    cancel.frame = CGRectMake(20 + (width - 44) / 2, 50, (width - 44) / 2, 36);
    cancel.layer.cornerRadius = 6;
    cancel.layer.borderWidth = 1;
    cancel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.4].CGColor;
    cancel.titleLabel.font = ZLBoldFont(15);
    [cancel setTitleColor:ZLTextColor() forState:UIControlStateNormal];
    [cancel setTitle:@"Cancel" forState:UIControlStateNormal];
    [cancel addTarget:view action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    [view addSubview:cancel];
    [view update];
    [window addSubview:view];
    view.timer = [NSTimer scheduledTimerWithTimeInterval:1 target:view selector:@selector(tick) userInfo:nil repeats:YES];
}

- (void)update {
    self.label.text = [NSString stringWithFormat:@"Next: %@\nStarts in %d s", self.name, self.left];
}

- (void)tick {
    self.left--;
    [self update];
    if (self.left <= 0) [self playNow];
}

- (void)playNow {
    void (^onPlay)(void) = self.onPlay;
    [self cancel];
    if (onPlay) onPlay();
}

- (void)cancel {
    [self.timer invalidate];
    self.timer = nil;
    self.onPlay = nil;
    [self removeFromSuperview];
}

@end

#pragma mark - Watch

@implementation ZLWatch

+ (NSString *)titleOf:(ZLMeta *)meta episode:(ZLEpisode *)episode {
    if (!episode) return meta.name;
    NSString *code = [episode code];
    return episode.title.length ? [NSString stringWithFormat:@"%@ %@ %@", meta.name, code, episode.title]
                                : [NSString stringWithFormat:@"%@ %@", meta.name, code];
}

+ (NSArray *)itemsForStreams:(NSArray *)streams from:(NSUInteger)index meta:(ZLMeta *)meta episode:(ZLEpisode *)episode {
    NSMutableArray *items = [NSMutableArray array];
    NSString *video = episode.identifier ?: meta.identifier;
    double resume = [[ZLLibrary shared] positionOf:video];
    for (NSUInteger i = index; i < streams.count && items.count < 5; i++) {
        ZLStream *stream = streams[i];
        ZLPlayItem *item = [ZLPlayItem itemWithURL:stream.URL title:[self titleOf:meta episode:episode]];
        item.headers = stream.headers;
        item.bingeGroup = stream.bingeGroup;
        NSString *name = [stream.name stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        item.sourceName = name.length ? [NSString stringWithFormat:@"%@: %@", stream.addonName, name] : stream.addonName;
        // Start where the video stopped, a few seconds before.
        item.startTime = resume > 30 ? resume - 5 : 0;
        NSString *group = stream.bingeGroup;
        item.onClose = ^(double position, double duration, BOOL ended) {
            [self closedMeta:meta episode:episode position:position duration:duration ended:ended bingeGroup:group];
        };
        [items addObject:item];
    }
    return items;
}

+ (void)closedMeta:(ZLMeta *)meta episode:(ZLEpisode *)episode position:(double)position duration:(double)duration
             ended:(BOOL)ended bingeGroup:(NSString *)bingeGroup {
    NSString *video = episode.identifier ?: meta.identifier;
    ZLLog(@"closed %@ at %.0f of %.0f, ended %d", video, position, duration, ended);
    if (ended) [[ZLLibrary shared] setVideo:video ofMeta:meta watched:YES];
    else if (position > 0) [[ZLLibrary shared] recordMeta:meta video:video position:position duration:duration];
    if (!ended || !episode || ![ZLSettings shared].playNextEpisode) return;
    // The library copy has the episodes, also when the page played before the
    // full title loaded. Without them, ask the addons.
    ZLMeta *known = [[ZLLibrary shared] itemFor:meta.identifier].meta;
    if (known.episodes.count) {
        [self countDownAfter:known bingeGroup:bingeGroup];
        return;
    }
    [[ZLAddonManager shared] loadMeta:meta.type identifier:meta.identifier completion:^(ZLMeta *full, NSError *error) {
        if (!full) return;
        [[ZLLibrary shared] updateMeta:full];
        [self countDownAfter:full bingeGroup:bingeGroup];
    }];
}

+ (void)countDownAfter:(ZLMeta *)meta bingeGroup:(NSString *)bingeGroup {
    ZLEpisode *next = [[ZLLibrary shared] nextEpisodeOf:meta];
    if (!next) return;
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    UIViewController *controller = window.rootViewController;
    while (controller.presentedViewController) controller = controller.presentedViewController;
    if ([controller isKindOfClass:[UITabBarController class]]) controller = ((UITabBarController *)controller).selectedViewController;
    if ([controller isKindOfClass:[UINavigationController class]]) controller = ((UINavigationController *)controller).topViewController;
    NSString *name = next.title.length ? [NSString stringWithFormat:@"%@ %@", [next code], next.title] : [next code];
    ZLLog(@"next episode %@", next.identifier);
    [ZLCountdownView showIn:window name:name onPlay:^{
        [self autoplay:meta episode:next bingeGroup:bingeGroup from:controller];
    }];
}

+ (void)autoplay:(ZLMeta *)meta episode:(ZLEpisode *)episode bingeGroup:(NSString *)bingeGroup
            from:(UIViewController *)controller {
    ZLCollectStreams(meta, episode, 8, ^(NSArray *streams) {
        ZLRankedStreams *ranked = ZLRankStreams(streams, NO);
        if (!ranked.streams.count) {
            UINavigationController *navigation = controller.navigationController;
            [navigation pushViewController:[[ZLStreamsViewController alloc] initWithMeta:meta episode:episode] animated:YES];
            return;
        }
        NSMutableArray *ordered = [ranked.streams mutableCopy];
        if (bingeGroup.length) {
            // The streams of the same group first, in their order.
            NSMutableArray *same = [NSMutableArray array];
            for (ZLStream *stream in ranked.streams) {
                if ([stream.bingeGroup isEqualToString:bingeGroup]) [same addObject:stream];
            }
            [ordered removeObjectsInArray:same];
            [ordered insertObjects:same atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, same.count)]];
        }
        [ZLPlayback playItems:[self itemsForStreams:ordered from:0 meta:meta episode:episode] from:controller];
    });
}

@end
