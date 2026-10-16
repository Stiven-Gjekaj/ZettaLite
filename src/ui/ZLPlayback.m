#import "ZLPlayback.h"
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import "ZLHLSServer.h"
#import "ZLInput.h"
#import "ZLLog.h"
#import "ZLMediaInfo.h"
#import "ZLPlayerEngine.h"
#import "ZLRemuxSession.h"
#import "ZLSettings.h"
#import "ZLSoftwarePlayerViewController.h"
#import "ZLTheme.h"
#import "ZLTrust.h"

@implementation ZLPlayItem

+ (instancetype)itemWithURL:(NSURL *)url title:(NSString *)title {
    ZLPlayItem *item = [ZLPlayItem new];
    item.URL = url;
    item.title = title;
    return item;
}

@end

#pragma mark - System player

// The system movie player. It keeps the remux session for as long as it shows.
@interface ZLSystemPlayerViewController : MPMoviePlayerViewController
@property (nonatomic, strong) ZLRemuxSession *session;
@property (nonatomic, copy) void (^onError)(void);
@property (nonatomic, copy) void (^onClose)(double position, double duration, BOOL ended);
@property (nonatomic) BOOL ended;
@property (nonatomic) BOOL failed;
@property (nonatomic) double lastPosition;
@property (nonatomic) double lastDuration;
@end

@implementation ZLSystemPlayerViewController

- (instancetype)initWithContentURL:(NSURL *)url {
    if ((self = [super initWithContentURL:url])) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(finished:)
                                                     name:MPMoviePlayerPlaybackDidFinishNotification
                                                   object:self.moviePlayer];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)finished:(NSNotification *)note {
    NSInteger reason = [note.userInfo[MPMoviePlayerPlaybackDidFinishReasonUserInfoKey] integerValue];
    if (reason == MPMovieFinishReasonPlaybackEnded) self.ended = YES;
    if (reason == MPMovieFinishReasonPlaybackError && self.onError) {
        self.failed = YES;
        void (^onError)(void) = self.onError;
        self.onError = nil;
        onError();
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.lastPosition = self.moviePlayer.currentPlaybackTime;
    self.lastDuration = self.moviePlayer.duration;
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.presentingViewController) return;
    if (self.session) {
        [[ZLHLSServer shared] removeSource:self.session];
        [self.session close];
        self.session = nil;
    }
    if (!self.failed && self.onClose) {
        double position = self.lastPosition;
        double duration = self.lastDuration;
        BOOL ended = self.ended || (duration > 0 && position >= duration - 2);
        void (^onClose)(double, double, BOOL) = self.onClose;
        self.onClose = nil;
        onClose(isnan(position) ? 0 : position, isnan(duration) ? 0 : duration, ended);
    }
}

@end

#pragma mark - Loading box

// A dark box with a spinner in the middle of the window. A tap cancels.
@interface ZLLoadingBox : UIControl
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UILabel *detail;
@end

@implementation ZLLoadingBox

+ (instancetype)showIn:(UIView *)parent {
    ZLLoadingBox *cover = [[ZLLoadingBox alloc] initWithFrame:parent.bounds];
    cover.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 220, 140)];
    box.center = CGPointMake(CGRectGetMidX(parent.bounds), CGRectGetMidY(parent.bounds));
    box.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                           UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    box.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
    box.layer.cornerRadius = 10;
    box.userInteractionEnabled = NO;
    UIActivityIndicatorView *spinner =
        [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    spinner.center = CGPointMake(110, 36);
    [spinner startAnimating];
    [box addSubview:spinner];
    cover.label = [[UILabel alloc] initWithFrame:CGRectMake(8, 64, 204, 20)];
    cover.label.text = @"Loading";
    cover.label.textColor = [UIColor whiteColor];
    cover.label.backgroundColor = [UIColor clearColor];
    cover.label.textAlignment = NSTextAlignmentCenter;
    cover.label.font = ZLBoldFont(15);
    [box addSubview:cover.label];
    cover.detail = [[UILabel alloc] initWithFrame:CGRectMake(8, 84, 204, 30)];
    cover.detail.textColor = [UIColor colorWithWhite:1 alpha:0.75];
    cover.detail.backgroundColor = [UIColor clearColor];
    cover.detail.textAlignment = NSTextAlignmentCenter;
    cover.detail.font = ZLFont(12);
    cover.detail.numberOfLines = 2;
    [box addSubview:cover.detail];
    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(0, 116, 220, 16)];
    hint.text = @"Tap to cancel";
    hint.textColor = [UIColor colorWithWhite:1 alpha:0.5];
    hint.backgroundColor = [UIColor clearColor];
    hint.textAlignment = NSTextAlignmentCenter;
    hint.font = ZLFont(11);
    [box addSubview:hint];
    [cover addSubview:box];
    [parent addSubview:cover];
    return cover;
}

@end

#pragma mark - Playback

@interface ZLPlayback () <UIAlertViewDelegate>
@property (nonatomic, copy) NSArray *items;
@property (nonatomic) NSUInteger index;
@property (nonatomic, weak) UIViewController *controller;
@property (nonatomic, strong) ZLLoadingBox *loading;
@property (nonatomic, strong) ZLInput *input;
@property (atomic) BOOL cancelled;
@property (nonatomic, copy) NSString *askedHost;
@property (nonatomic) BOOL skipNative;
@property (nonatomic, strong) NSError *lastError;
@end

// The playback that runs now. It keeps itself alive until it ends.
static ZLPlayback *ZLCurrentPlayback;

@implementation ZLPlayback

+ (void)play:(ZLPlayItem *)item from:(UIViewController *)controller {
    [self playItems:@[ item ] from:controller];
}

+ (void)playItems:(NSArray *)items from:(UIViewController *)controller {
    if (!items.count) return;
    [ZLCurrentPlayback cancel];
    ZLPlayback *playback = [ZLPlayback new];
    playback.items = items;
    playback.controller = controller;
    ZLCurrentPlayback = playback;
    [playback start];
}

- (ZLPlayItem *)item {
    return self.items[self.index];
}

- (void)start {
    UIView *window = self.controller.view.window;
    if (!window) {
        [self end];
        return;
    }
    if (!self.loading) {
        self.loading = [ZLLoadingBox showIn:window];
        [self.loading addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    }
    ZLPlayItem *item = self.item;
    self.loading.label.text = self.items.count > 1 ? [NSString stringWithFormat:@"Source %lu of %lu",
                                                      (unsigned long)self.index + 1, (unsigned long)self.items.count]
                                                   : @"Loading";
    self.loading.detail.text = item.sourceName ?: item.title;
    if ([self playsNatively]) {
        [self showSystemPlayer:item.URL session:nil];
        return;
    }
    ZLLog(@"play %@", item.URL);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSError *error = nil;
        ZLInput *input = [ZLInput openURL:item.URL headers:item.headers error:&error];
        self.input = input;
        ZLLog(@"open %@", input ? @"done" : error.localizedDescription);
        ZLMediaInfo *info = input ? [ZLMediaInfo infoForInput:input languages:[[ZLSettings shared] audioLanguages]] : nil;
        ZLRemuxSession *session = nil;
        if (input && info.route == ZLRouteSystem) {
            session = [[ZLRemuxSession alloc] initWithInput:input info:info audioIndex:-1];
            if (![session prepare:&error]) session = nil;
            ZLLog(@"prepare %@, %lu segments", session ? @"done" : error.localizedDescription, (unsigned long)session.segmentCount);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.cancelled || item != self.item) {
                [session close];
                [input close];
                return;
            }
            if (!input) {
                [self failWith:error];
            } else if (info.route == ZLRouteNone) {
                [input close];
                [self failWith:ZLMakeError(ZLErrorMedia, info.reason)];
            } else if (info.route == ZLRouteSoftware) {
                [self showSoftwarePlayer:input info:info];
            } else if (!session) {
                [input close];
                [self failWith:error];
            } else {
                NSURL *url = [[ZLHLSServer shared] addSource:session];
                [self showSystemPlayer:url session:session];
            }
        });
    });
}

// An HLS playlist with no headers goes to the system player as it is, when
// the user did not have to trust the host. FFmpeg is the fallback.
- (BOOL)playsNatively {
    if (self.skipNative || self.item.headers.count) return NO;
    if (![self.item.URL.pathExtension.lowercaseString isEqualToString:@"m3u8"]) return NO;
    return ![[ZLTrust shared] isTrusted:self.item.URL.host];
}

- (void)showSystemPlayer:(NSURL *)url session:(ZLRemuxSession *)session {
    [self.loading removeFromSuperview];
    self.loading = nil;
    ZLPlayItem *item = self.item;
    ZLSystemPlayerViewController *player = [[ZLSystemPlayerViewController alloc] initWithContentURL:url];
    player.session = session;
    player.onClose = item.onClose;
    player.moviePlayer.movieSourceType = MPMovieSourceTypeStreaming;
    if (item.startTime > 0) player.moviePlayer.initialPlaybackTime = item.startTime;
    __weak ZLSystemPlayerViewController *weakPlayer = player;
    player.onError = ^{
        [weakPlayer.presentingViewController dismissMoviePlayerViewControllerAnimated];
        ZLLog(@"system player error with %@", item.URL);
        if (!session) {
            // The system player failed with the playlist. Try FFmpeg.
            self.skipNative = YES;
            [self start];
        } else {
            [self failWith:ZLMakeError(ZLErrorMedia, @"The player could not play the stream.")];
        }
    };
    [self.controller presentMoviePlayerViewControllerAnimated:player];
}

// The own player decodes the video in software.
- (void)showSoftwarePlayer:(ZLInput *)input info:(ZLMediaInfo *)info {
    ZLLog(@"software player: %@", info.reason);
    ZLPlayerEngine *engine = [[ZLPlayerEngine alloc] initWithInput:input info:info];
    NSError *error = nil;
    if (![engine startAt:self.item.startTime error:&error]) {
        [engine close];
        [self failWith:error];
        return;
    }
    [self.loading removeFromSuperview];
    self.loading = nil;
    ZLSoftwarePlayerViewController *player = [[ZLSoftwarePlayerViewController alloc] initWithEngine:engine];
    player.titleText = self.item.title;
    void (^onClose)(double, double, BOOL) = self.item.onClose;
    player.onClose = ^(double position, double duration) {
        if (onClose) onClose(position, duration, duration > 0 && position >= duration - 2);
    };
    [self.controller presentViewController:player animated:YES completion:nil];
    [self end];
}

- (void)failWith:(NSError *)error {
    if ([error.domain isEqualToString:ZLErrorDomain] && error.code == ZLErrorUntrustedHost) {
        self.askedHost = error.userInfo[ZLUntrustedHostKey];
        [self.loading removeFromSuperview];
        self.loading = nil;
        NSString *text = [NSString stringWithFormat:@"The certificate of %@ is not valid. Somebody can read or change "
                                                    @"the data. Trust this host from now on?", self.askedHost];
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Trust this host?" message:text delegate:self
                                              cancelButtonTitle:@"Cancel" otherButtonTitles:@"Trust", nil];
        [alert show];
        return;
    }
    self.lastError = error;
    ZLLog(@"source %lu failed: %@", (unsigned long)self.index + 1, error.localizedDescription);
    if (self.index + 1 < self.items.count) {
        // The next source.
        self.index++;
        self.skipNative = NO;
        [self start];
        return;
    }
    NSString *title = self.items.count > 1 ? @"No source plays" : @"Cannot open the link";
    [self showError:title text:error.localizedDescription];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex != alertView.cancelButtonIndex && self.askedHost) {
        [[ZLTrust shared] trustHost:self.askedHost];
        self.askedHost = nil;
        self.skipNative = YES;
        [self start];
    } else if (self.index + 1 < self.items.count) {
        self.index++;
        [self start];
    } else {
        [self end];
    }
}

- (void)showError:(NSString *)title text:(NSString *)text {
    [self.loading removeFromSuperview];
    self.loading = nil;
    [[[UIAlertView alloc] initWithTitle:title message:text delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    [self end];
}

- (void)cancel {
    self.cancelled = YES;
    [self.input cancel];
    [self.loading removeFromSuperview];
    self.loading = nil;
    [self end];
}

- (void)end {
    if (ZLCurrentPlayback == self) ZLCurrentPlayback = nil;
}

@end
