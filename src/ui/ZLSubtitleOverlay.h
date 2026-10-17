// Shows subtitles over a player. The choices are the text subtitles inside
// the file and the subtitles of the addons. The overlay picks the language of
// Settings at the start. The player calls showAt: with its position.

#import <UIKit/UIKit.h>
#import "ZLEmbeddedSubtitles.h"
#import "ZLMediaInfo.h"
#import "ZLPlayback.h"

@interface ZLSubtitleOverlay : NSObject

// A view to put over the video. It fills its parent and takes no touches.
@property (nonatomic, readonly) UIView *view;
// The label of the subtitles that show, or nil for none.
@property (nonatomic, readonly) NSString *currentLabel;
// Space at the bottom for the controls of the player, in points.
@property (nonatomic) CGFloat bottomInset;

- (instancetype)initWithItem:(ZLPlayItem *)item info:(ZLMediaInfo *)info embedded:(ZLEmbeddedSubtitles *)embedded;

- (void)showAt:(double)seconds;

// Shows a sheet with the choices.
- (void)showPickerInView:(UIView *)view;

@end
