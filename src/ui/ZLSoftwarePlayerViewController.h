// The screen of the own player. Its controls look like the controls of the
// system player: Done, play and pause, a seek bar, and pickers for the
// audio track and the subtitles.

#import <UIKit/UIKit.h>
#import "ZLPlayerEngine.h"
#import "ZLSubtitleOverlay.h"

@interface ZLSoftwarePlayerViewController : UIViewController
@property (nonatomic, copy) NSString *titleText;
// Set before the screen shows. nil gives no Subtitles button.
@property (nonatomic, strong) ZLSubtitleOverlay *subtitles;
// Called with the position when the screen closes. The library keeps it.
@property (nonatomic, copy) void (^onClose)(double position, double duration);
- (instancetype)initWithEngine:(ZLPlayerEngine *)engine;
@end
