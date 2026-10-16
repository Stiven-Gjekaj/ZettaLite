// Shows the frames of the own player with OpenGL ES 2. A shader changes
// YUV into RGB, so the CPU does no color work.

#import <UIKit/UIKit.h>
#import "ZLPlayerEngine.h"

typedef NS_ENUM(NSInteger, ZLVideoGravity) {
    ZLVideoGravityFit,   // The full picture, with black bars.
    ZLVideoGravityFill,  // The full screen. The edges of the picture are cut.
};

@interface ZLVideoView : UIView
@property (nonatomic) ZLVideoGravity gravity;
- (void)showFrame:(ZLVideoFrame *)frame;
// Draws the last frame again, for example after a rotation.
- (void)redraw;
// Frees the GL objects. Call it before the app goes to the background.
- (void)releaseGL;
@end
