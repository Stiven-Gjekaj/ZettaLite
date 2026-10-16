// A tab with an empty state, for a part that a later release fills.

#import <UIKit/UIKit.h>

@interface ZLPlaceholderViewController : UIViewController
- (instancetype)initWithTitle:(NSString *)title image:(NSString *)image tag:(NSInteger)tag text:(NSString *)text;
@end
