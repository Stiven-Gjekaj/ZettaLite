// The streams of a film or an episode, from all addons at the same time, best
// first. Each stream shows its badges and all of its text. Torrent streams
// and, by default, the streams that are too heavy do not show.

#import <UIKit/UIKit.h>
#import "ZLMeta.h"

@class ZLPlayItem;

@interface ZLStreamsViewController : UITableViewController
// episode is nil for a film.
- (instancetype)initWithMeta:(ZLMeta *)meta episode:(ZLEpisode *)episode;
@end

// Collects the streams of all addons. It calls back when all addons answered
// or after the time limit.
void ZLCollectStreams(ZLMeta *meta, ZLEpisode *episode, NSTimeInterval limit, void (^completion)(NSArray *streams));
