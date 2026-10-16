// The page of a title: the picture, the facts, Play, the description, the
// cast, the episodes of a series, and "More like this".

#import <UIKit/UIKit.h>
#import "ZLMeta.h"

@interface ZLTitleViewController : UITableViewController
- (instancetype)initWithMeta:(ZLMeta *)meta;
// Plays this episode or film. The stream picker comes from here.
- (void)playEpisode:(ZLEpisode *)episode;
@end
