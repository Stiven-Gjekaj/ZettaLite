#import "ZLEmptyView.h"
#import <QuartzCore/QuartzCore.h>
#import "ZLTheme.h"

@interface ZLEmptyView ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *textLabel;
@property (nonatomic, strong) UIButton *button;
@end

@implementation ZLEmptyView

- (instancetype)initWithTitle:(NSString *)title text:(NSString *)text button:(NSString *)button
                       target:(id)target action:(SEL)action {
    if ((self = [super initWithFrame:CGRectMake(0, 0, 320, 240)])) {
        self.backgroundColor = ZLBackgroundColor();
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.titleLabel = [UILabel new];
        self.titleLabel.text = title;
        self.titleLabel.font = ZLBoldFont(20);
        self.titleLabel.textColor = ZLTextColor();
        self.titleLabel.backgroundColor = [UIColor clearColor];
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:self.titleLabel];
        self.textLabel = [UILabel new];
        self.textLabel.text = text;
        self.textLabel.font = ZLFont(15);
        self.textLabel.textColor = ZLSecondaryTextColor();
        self.textLabel.backgroundColor = [UIColor clearColor];
        self.textLabel.textAlignment = NSTextAlignmentCenter;
        self.textLabel.numberOfLines = 0;
        [self addSubview:self.textLabel];
        if (button) {
            self.button = [UIButton buttonWithType:UIButtonTypeCustom];
            [self.button setTitle:button forState:UIControlStateNormal];
            [self.button setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
            self.button.titleLabel.font = ZLBoldFont(16);
            self.button.backgroundColor = ZLAccentColor();
            self.button.layer.cornerRadius = 8;
            [self.button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
            [self addSubview:self.button];
        }
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    CGSize size = [self.textLabel.text sizeWithFont:self.textLabel.font constrainedToSize:CGSizeMake(width - 60, 400)];
    CGFloat total = 30 + 10 + size.height + (self.button ? 64 : 0);
    CGFloat y = MAX(20, (self.bounds.size.height - total) / 2 - 20);
    self.titleLabel.frame = CGRectMake(20, y, width - 40, 30);
    self.textLabel.frame = CGRectMake(30, y + 40, width - 60, size.height);
    self.button.frame = CGRectMake((width - 220) / 2, y + 40 + size.height + 20, 220, 44);
}

@end
