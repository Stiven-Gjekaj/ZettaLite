// A screen with a box for one link. Play plays the link at once.

#import <UIKit/UIKit.h>

@interface ZLLinkViewController : UIViewController
- (void)playURL:(NSURL *)url title:(NSString *)title startTime:(double)startTime;
@end
