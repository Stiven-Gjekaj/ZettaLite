#import "ZLPlayback.h"
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import "ZLHLSServer.h"
#import "ZLInput.h"
#import "ZLLog.h"
#import "ZLMediaInfo.h"
#import "ZLDecodeLimits.h"
#import "ZLPlayerEngine.h"
#import "ZLSoftwarePlayerViewController.h"
#import "ZLRemuxSession.h"
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
    NSNumber *reason = note.userInfo[MPMoviePlayerPlaybackDidFinishReasonUserInfoKey];
    if (reason.integerValue == MPMovieFinishReasonPlaybackError && self.onError) {
        void (^onError)(void) = self.onError;
        self.onError = nil;
        onError();
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.session && !self.presentingViewController) {
        [[ZLHLSServer shared] removeSource:self.session];
        [self.session close];
        self.session = nil;
    }
}

@end

#pragma mark - Loading box

// A dark box with a spinner in the middle of the window. A tap cancels.
@interface ZLLoadingBox : UIControl
@property (nonatomic, strong) UILabel *label;
@end

@implementation ZLLoadingBox

+ (instancetype)showIn:(UIView *)parent {
    ZLLoadingBox *cover = [[ZLLoadingBox alloc] initWithFrame:parent.bounds];
    cover.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 150, 120)];
    box.center = CGPointMake(CGRectGetMidX(parent.bounds), CGRectGetMidY(parent.bounds));
    box.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                           UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    box.backgroundColor = [UIColor colorWithWhite:0 alpha:0.8];
    box.layer.cornerRadius = 10;
    box.userInteractionEnabled = NO;
    UIActivityIndicatorView *spinner =
        [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    spinner.center = CGPointMake(75, 40);
    [spinner startAnimating];
    [box addSubview:spinner];
    cover.label = [[UILabel alloc] initWithFrame:CGRectMake(0, 70, 150, 20)];
    cover.label.text = @"Loading";
    cover.label.textColor = [UIColor whiteColor];
    cover.label.backgroundColor = [UIColor clearColor];
    cover.label.textAlignment = NSTextAlignmentCenter;
    cover.label.font = ZLBoldFont(15);
    [box addSubview:cover.label];
    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(0, 92, 150, 16)];
    hint.text = @"Tap to cancel";
    hint.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    hint.backgroundColor = [UIColor clearColor];
    hint.textAlignment = NSTextAlignmentCenter;
    hint.font = ZLFont(12);
    [box addSubview:hint];
    [cover addSubview:box];
    [parent addSubview:cover];
    return cover;
}

@end

#pragma mark - Playback

@interface ZLPlayback () <UIAlertViewDelegate>
@property (nonatomic, strong) ZLPlayItem *item;
@property (nonatomic, weak) UIViewController *controller;
@property (nonatomic, strong) ZLLoadingBox *loading;
@property (nonatomic, strong) ZLInput *input;
@property (atomic) BOOL cancelled;
@property (nonatomic, copy) NSString *askedHost;
@property (nonatomic) BOOL skipNative;
@end

// The playback that runs now. It keeps itself alive until it ends.
static ZLPlayback *ZLCurrentPlayback;

@implementation ZLPlayback

+ (void)play:(ZLPlayItem *)item from:(UIViewController *)controller {
    [ZLCurrentPlayback cancel];
    ZLPlayback *playback = [ZLPlayback new];
    playback.item = item;
    playback.controller = controller;
    ZLCurrentPlayback = playback;
    [playback start];
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
    if ([self playsNatively]) {
        [self showSystemPlayer:self.item.URL session:nil];
        return;
    }
    ZLPlayItem *item = self.item;
    ZLLog(@"play %@", item.URL);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSError *error = nil;
        ZLInput *input = [ZLInput openURL:item.URL headers:item.headers error:&error];
        ZLLog(@"open %@", input ? @"done" : error.localizedDescription);
        self.input = input;
        ZLMediaInfo *info = input ? [ZLMediaInfo infoForInput:input languages:[self preferredLanguages]] : nil;
        ZLRemuxSession *session = nil;
        if (input && info.route == ZLRouteSystem) {
            session = [[ZLRemuxSession alloc] initWithInput:input info:info audioIndex:-1];
            if (![session prepare:&error]) session = nil;
            ZLLog(@"prepare %@, %lu segments", session ? @"done" : error.localizedDescription, (unsigned long)session.segmentCount);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.cancelled) {
                [session close];
                [input close];
                return;
            }
            if (!input) {
                [self failWith:error];
            } else if (info.route == ZLRouteNone) {
                [input close];
                [self showError:@"The video does not play" text:info.reason];
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
// the system trusts the host. FFmpeg is the fallback.
- (BOOL)playsNatively {
    if (self.skipNative || self.item.headers.count) return NO;
    if (![self.item.URL.pathExtension.lowercaseString isEqualToString:@"m3u8"]) return NO;
    return ![[ZLTrust shared] isTrusted:self.item.URL.host];
}

- (NSArray *)preferredLanguages {
    NSString *language = [[NSLocale preferredLanguages] firstObject];
    NSString *code = language.length >= 2 ? [language substringToIndex:2] : @"en";
    // ISO 639-1 to ISO 639-2 for the common languages.
    NSDictionary *map = @{ @"en": @"eng", @"de": @"ger", @"fr": @"fre", @"es": @"spa", @"it": @"ita",
                           @"pt": @"por", @"ja": @"jpn", @"sq": @"alb", @"ru": @"rus", @"nl": @"dut" };
    return map[code] ? @[ map[code] ] : @[];
}

- (void)showSystemPlayer:(NSURL *)url session:(ZLRemuxSession *)session {
    [self.loading removeFromSuperview];
    self.loading = nil;
    ZLSystemPlayerViewController *player = [[ZLSystemPlayerViewController alloc] initWithContentURL:url];
    player.session = session;
    player.moviePlayer.movieSourceType = MPMovieSourceTypeStreaming;
    if (self.item.startTime > 0) player.moviePlayer.initialPlaybackTime = self.item.startTime;
    __weak ZLSystemPlayerViewController *weakPlayer = player;
    player.onError = ^{
        [weakPlayer.presentingViewController dismissMoviePlayerViewControllerAnimated];
        if (!session) {
            // The system player failed with the playlist. Try FFmpeg.
            self.skipNative = YES;
            [self start];
        } else {
            [self showError:@"The video stopped" text:@"The player could not play the stream."];
        }
    };
    [self.controller presentMoviePlayerViewControllerAnimated:player];
    if (session) [self end];
}

// The own player decodes the video in software.
- (void)showSoftwarePlayer:(ZLInput *)input info:(ZLMediaInfo *)info {
    ZLLog(@"software player: %@", info.reason);
    ZLPlayerEngine *engine = [[ZLPlayerEngine alloc] initWithInput:input info:info];
    NSError *error = nil;
    if (![engine startAt:self.item.startTime error:&error]) {
        [engine close];
        [self showError:@"The video does not play" text:error.localizedDescription];
        return;
    }
    [self.loading removeFromSuperview];
    self.loading = nil;
    ZLSoftwarePlayerViewController *player = [[ZLSoftwarePlayerViewController alloc] initWithEngine:engine];
    player.titleText = self.item.title;
    [self.controller presentViewController:player animated:YES completion:nil];
    [self end];
}

- (void)failWith:(NSError *)error {
    if ([error.domain isEqualToString:ZLErrorDomain] && error.code == ZLErrorUntrustedHost) {
        self.askedHost = error.userInfo[ZLUntrustedHostKey];
        [self.loading removeFromSuperview];
        self.loading = nil;
        NSString *text = [NSString stringWithFormat:@"iOS 6 does not trust the certificate of %@. Somebody can read or "
                                                    @"change the data. Trust this host from now on?", self.askedHost];
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Trust this host?" message:text delegate:self
                                              cancelButtonTitle:@"Cancel" otherButtonTitles:@"Trust", nil];
        [alert show];
        return;
    }
    [self showError:@"Cannot open the link" text:error.localizedDescription];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex != alertView.cancelButtonIndex && self.askedHost) {
        [[ZLTrust shared] trustHost:self.askedHost];
        self.askedHost = nil;
        self.skipNative = YES;
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
