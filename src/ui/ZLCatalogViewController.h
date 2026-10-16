// All the titles of one catalog in a grid. More titles load at the end.

#import <UIKit/UIKit.h>
#import "ZLAddon.h"

@interface ZLCatalogViewController : UICollectionViewController
- (instancetype)initWithCatalog:(ZLCatalog *)catalog extras:(NSDictionary *)extras;
@end
