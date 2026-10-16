// A row of Home: a title over a horizontal list of posters.

#import <UIKit/UIKit.h>
#import "ZLMeta.h"

@class ZLRowCell;

@protocol ZLRowCellDelegate <NSObject>
- (void)rowCell:(ZLRowCell *)cell didSelectMeta:(ZLMeta *)meta atIndex:(NSUInteger)index;
// The title of the row was tapped, to see all of its titles.
- (void)rowCellDidSelectTitle:(ZLRowCell *)cell;
@end

extern const CGFloat ZLRowCellHeight;

@interface ZLRowCell : UITableViewCell
@property (nonatomic, weak) id<ZLRowCellDelegate> delegate;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSArray *metas;
// A badge and a progress for each title, or nil.
@property (nonatomic, copy) NSArray *badges;
@property (nonatomic, copy) NSArray *progress;
@property (nonatomic) BOOL loading;
@property (nonatomic, copy) NSString *message;  // Shows when there are no titles.
@property (nonatomic) BOOL showsMore;
// Keeps the place of the row when the table uses the cell again.
@property (nonatomic) CGFloat offset;
@property (nonatomic, readonly) UICollectionView *collection;
@end
