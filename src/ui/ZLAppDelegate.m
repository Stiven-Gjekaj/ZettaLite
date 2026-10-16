#import "ZLAppDelegate.h"
#import <AVFoundation/AVFoundation.h>
#import "ZLHLSServer.h"
#import "ZLLink.h"
#import "ZLLinkViewController.h"
#import "ZLNavigationController.h"
#import "ZLTheme.h"
#include <libavutil/log.h>

@interface ZLAppDelegate ()
@property (nonatomic, strong) ZLLinkViewController *linkScreen;
@end

@implementation ZLAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Play the sound also when the ring switch is off, and when the screen locks.
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:NULL];
    [[ZLHLSServer shared] start:NULL];
    av_log_set_level(AV_LOG_ERROR);
    ZLApplyTheme();

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = ZLBackgroundColor();
    self.linkScreen = [ZLLinkViewController new];
    self.window.rootViewController = [[ZLNavigationController alloc] initWithRootViewController:self.linkScreen];
    [self.window makeKeyAndVisible];
    // iOS calls application:openURL: after this method for a launch from a
    // link, so this method does not open the link.
    return YES;
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication
         annotation:(id)annotation {
    ZLLink *link = ZLParseLink(url);
    if (!link) return NO;
    // A link can come while a player shows. Close it first.
    [self.window.rootViewController dismissViewControllerAnimated:NO completion:nil];
    [self.linkScreen playURL:link.mediaURL title:link.title];
    return YES;
}

@end
