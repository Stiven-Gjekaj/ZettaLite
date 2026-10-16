// The screen of the own player. Its controls look like the controls of the
// system player: Done, play and pause, a seek bar, and a picker for the
// audio track.

#import <UIKit/UIKit.h>
#import "ZLPlayerEngine.h"

@interface ZLSoftwarePlayerViewController : UIViewController
@property (nonatomic, copy) NSString *titleText;
// Called with the position when the screen closes. The library keeps it.
@property (nonatomic, copy) void (^onClose)(double position, double duration);
- (instancetype)initWithEngine:(ZLPlayerEngine *)engine;
@end
