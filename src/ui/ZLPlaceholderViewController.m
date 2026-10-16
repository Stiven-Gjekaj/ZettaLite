#import "ZLPlaceholderViewController.h"
#import "ZLEmptyView.h"

@interface ZLPlaceholderViewController ()
@property (nonatomic, copy) NSString *text;
@end

@implementation ZLPlaceholderViewController

- (instancetype)initWithTitle:(NSString *)title image:(NSString *)image tag:(NSInteger)tag text:(NSString *)text {
    if ((self = [super init])) {
        self.title = title;
        self.tabBarItem = [[UITabBarItem alloc] initWithTitle:title image:[UIImage imageNamed:image] tag:tag];
        _text = [text copy];
    }
    return self;
}

- (void)loadView {
    self.view = [[ZLEmptyView alloc] initWithTitle:self.title text:self.text button:nil target:nil action:NULL];
}

@end
