// The streams of a film or an episode, from all addons at the same time.
// Torrent streams do not show, because the app has no torrent engine.

#import <UIKit/UIKit.h>
#import "ZLMeta.h"

@interface ZLStreamsViewController : UITableViewController
// episode is nil for a film.
- (instancetype)initWithMeta:(ZLMeta *)meta episode:(ZLEpisode *)episode;
@end
