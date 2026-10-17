#import "ZLAppDelegate.h"
#import <AVFoundation/AVFoundation.h>
#import "ZLAddonManager.h"
#import "ZLHLSServer.h"
#import "ZLHomeViewController.h"
#import "ZLLibraryViewController.h"
#import "ZLLink.h"
#import "ZLLog.h"
#import "ZLLiveViewController.h"
#import "ZLNavigationController.h"
#import "ZLPlayback.h"
#import "ZLSearchViewController.h"
#import "ZLSettingsViewController.h"
#import "ZLTabBarController.h"
#import "ZLTheme.h"
#import "ZLTitleViewController.h"
#include <libavutil/log.h>

NSString *const ZLShowSourcesNotification = @"ZLShowSources";

@interface ZLAppDelegate ()
@property (nonatomic, strong) ZLTabBarController *tabs;
@property (nonatomic, strong) ZLSettingsViewController *settings;
@property (nonatomic, strong) ZLSearchViewController *search;
@property (nonatomic, strong) ZLLiveViewController *live;
@end

@implementation ZLAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Play the sound also when the ring switch is off, and when the screen locks.
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:NULL];
    [[ZLHLSServer shared] start:NULL];
    av_log_set_level(AV_LOG_ERROR);
    ZLApplyTheme();

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor blackColor];
    self.settings = [ZLSettingsViewController new];
    self.search = [ZLSearchViewController new];
    self.live = [ZLLiveViewController new];
    self.tabs = [ZLTabBarController new];
    self.tabs.viewControllers = @[
        [[ZLNavigationController alloc] initWithRootViewController:[ZLHomeViewController new]],
        [[ZLNavigationController alloc] initWithRootViewController:self.search],
        [[ZLNavigationController alloc] initWithRootViewController:[ZLLibraryViewController new]],
        [[ZLNavigationController alloc] initWithRootViewController:
            self.live],
        [[ZLNavigationController alloc] initWithRootViewController:self.settings],
    ];
    self.window.rootViewController = self.tabs;
    [self.window makeKeyAndVisible];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showSources)
                                                 name:ZLShowSourcesNotification object:nil];
    [[ZLAddonManager shared] reload];
    // iOS calls application:openURL: after this method for a launch from a
    // link, so this method does not open the link.
    return YES;
}

- (void)showSources {
    self.tabs.selectedIndex = 4;
    [self.settings showSources];
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication
         annotation:(id)annotation {
    ZLLog(@"link %@", url);
    ZLLink *link = ZLParseLink(url);
    if (!link) return NO;
    // A link can come while a player shows. Close it first.
    [self.tabs dismissViewControllerAnimated:NO completion:nil];
    NSArray *names = @[ @"home", @"search", @"library", @"live", @"settings" ];
    switch (link.kind) {
        case ZLLinkTab: {
            self.tabs.selectedIndex = [names indexOfObject:link.text];
            UINavigationController *navigation = (UINavigationController *)self.tabs.selectedViewController;
            [navigation popToRootViewControllerAnimated:NO];
            break;
        }
        case ZLLinkLive:
            self.tabs.selectedIndex = 3;
            [self.live.navigationController popToRootViewControllerAnimated:NO];
            if (link.text) [self.live openGroup:link.text];
            if (link.title) [self.live playChannelNamed:link.title];
            break;
        case ZLLinkSearch:
            self.tabs.selectedIndex = 1;
            [self.search.navigationController popToRootViewControllerAnimated:NO];
            [self.search searchFor:link.text];
            break;
        case ZLLinkTitle:
        case ZLLinkWatch: {
            // An episode ID is the ID of the series, then the season and the episode.
            NSString *titleID = link.identifier;
            ZLEpisode *episode = nil;
            NSArray *parts = [link.identifier componentsSeparatedByString:@":"];
            if ([link.type isEqualToString:@"series"] && parts.count >= 3) {
                titleID = [[parts subarrayWithRange:NSMakeRange(0, parts.count - 2)] componentsJoinedByString:@":"];
                episode = [ZLEpisode episodeWithJSON:@{ @"id": link.identifier, @"season": parts[parts.count - 2],
                                                        @"episode": parts[parts.count - 1] }];
            }
            ZLMeta *meta = [ZLMeta metaWithJSON:@{ @"id": titleID, @"type": link.type, @"name": titleID }];
            self.tabs.selectedIndex = 0;
            UINavigationController *home = (UINavigationController *)self.tabs.selectedViewController;
            ZLTitleViewController *page = [[ZLTitleViewController alloc] initWithMeta:meta];
            [home pushViewController:page animated:NO];
            if (link.kind == ZLLinkWatch) [page playEpisode:episode];
            break;
        }
        case ZLLinkPlay: {
            ZLPlayItem *item = [ZLPlayItem itemWithURL:link.mediaURL title:link.title ?: link.mediaURL.lastPathComponent];
            item.startTime = link.startTime;
            UIViewController *visible = self.tabs.selectedViewController;
            if ([visible isKindOfClass:[UINavigationController class]]) visible = ((UINavigationController *)visible).topViewController;
            [ZLPlayback play:item from:visible];
            break;
        }
    }
    return YES;
}

@end
