// A message in the middle of an empty screen, with an optional button.

#import <UIKit/UIKit.h>

@interface ZLEmptyView : UIView
- (instancetype)initWithTitle:(NSString *)title text:(NSString *)text button:(NSString *)button
                       target:(id)target action:(SEL)action;
@end
