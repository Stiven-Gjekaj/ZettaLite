// A poster with the title and the facts under it, for the rows and the grids.

#import <UIKit/UIKit.h>
#import "ZLMeta.h"

// The size of a poster cell in points.
extern const CGSize ZLPosterCellSize;

@interface ZLPosterCell : UICollectionViewCell
@property (nonatomic, strong) ZLMeta *meta;
// A small line over the poster, for example "S2 E5" or "45%".
@property (nonatomic, copy) NSString *badge;
// The part that the user watched, from 0 to 1. 0 shows no bar.
@property (nonatomic) double progress;
@end
