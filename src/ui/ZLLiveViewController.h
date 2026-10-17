// The Live TV tab. The first screen shows the favourite channels and the
// groups. A group shows its channels. The search bar finds a channel by name
// in all the groups. A tap plays a channel. The star marks a favourite.

#import <UIKit/UIKit.h>

@interface ZLLiveViewController : UITableViewController
// The first screen of the tab.
- (instancetype)init;
// The channels of one group.
- (instancetype)initWithGroup:(NSString *)group;
// Shows a group. When the channels load now, it waits for them.
- (void)openGroup:(NSString *)group;
// Plays the first channel with this name. It ignores the case.
- (void)playChannelNamed:(NSString *)name;
@end
