#import "ZLPosterCell.h"
#import <QuartzCore/QuartzCore.h>
#import "ZLImageLoader.h"
#import "ZLTheme.h"

const CGSize ZLPosterCellSize = {96, 186};
static const CGFloat ZLPosterHeight = 144;

@interface ZLPosterCell ()
@property (nonatomic, strong) UIImageView *poster;
@property (nonatomic, strong) UILabel *placeholder;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *factsLabel;
@property (nonatomic, strong) UILabel *badgeLabel;
@property (nonatomic, strong) UIView *progressTrack;
@property (nonatomic, strong) UIView *progressBar;
@end

@implementation ZLPosterCell

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        CGFloat width = frame.size.width;
        self.poster = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, width, ZLPosterHeight)];
        self.poster.backgroundColor = ZLSurfaceColor();
        self.poster.contentMode = UIViewContentModeScaleAspectFill;
        self.poster.clipsToBounds = YES;
        self.poster.layer.cornerRadius = 4;
        [self.contentView addSubview:self.poster];
        self.placeholder = [[UILabel alloc] initWithFrame:CGRectInset(self.poster.frame, 6, 6)];
        self.placeholder.numberOfLines = 0;
        self.placeholder.textAlignment = NSTextAlignmentCenter;
        self.placeholder.font = ZLBoldFont(13);
        self.placeholder.textColor = ZLSecondaryTextColor();
        self.placeholder.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:self.placeholder];
        self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, ZLPosterHeight + 4, width, 16)];
        self.titleLabel.font = ZLBoldFont(12);
        self.titleLabel.textColor = ZLTextColor();
        self.titleLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:self.titleLabel];
        self.factsLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, ZLPosterHeight + 20, width, 14)];
        self.factsLabel.font = ZLFont(11);
        self.factsLabel.textColor = ZLSecondaryTextColor();
        self.factsLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:self.factsLabel];
        self.badgeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        self.badgeLabel.font = ZLBoldFont(10);
        self.badgeLabel.textColor = [UIColor blackColor];
        self.badgeLabel.backgroundColor = ZLAccentColor();
        self.badgeLabel.textAlignment = NSTextAlignmentCenter;
        self.badgeLabel.layer.cornerRadius = 3;
        self.badgeLabel.hidden = YES;
        [self.contentView addSubview:self.badgeLabel];
        self.progressTrack = [[UIView alloc] initWithFrame:CGRectMake(4, ZLPosterHeight - 7, width - 8, 3)];
        self.progressTrack.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
        self.progressBar = [[UIView alloc] initWithFrame:CGRectZero];
        self.progressBar.backgroundColor = ZLAccentColor();
        [self.progressTrack addSubview:self.progressBar];
        [self.contentView addSubview:self.progressTrack];
        UIView *selected = [[UIView alloc] initWithFrame:self.poster.frame];
        selected.backgroundColor = [UIColor colorWithWhite:1 alpha:0.25];
        selected.layer.cornerRadius = 4;
        self.selectedBackgroundView = selected;
    }
    return self;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.poster.alpha = highlighted ? 0.6 : 1;
}

- (void)setMeta:(ZLMeta *)meta {
    _meta = meta;
    self.titleLabel.text = meta.name;
    NSMutableArray *facts = [NSMutableArray array];
    if (meta.releaseInfo.length) [facts addObject:meta.releaseInfo];
    if (meta.rating.length) [facts addObject:[NSString stringWithFormat:@"%@ IMDb", meta.rating]];
    self.factsLabel.text = [facts componentsJoinedByString:@"  "];
    self.placeholder.text = meta.name;
    CGSize size = self.poster.bounds.size;
    UIImage *cached = [[ZLImageLoader shared] cachedImageForURL:meta.poster size:size];
    self.poster.image = cached;
    self.placeholder.hidden = cached != nil;
    if (cached || !meta.poster) return;
    NSURL *url = meta.poster;
    [[ZLImageLoader shared] loadURL:url size:size handler:^(UIImage *image) {
        // The cell can show another title now.
        if (![self.meta.poster isEqual:url] || !image) return;
        self.poster.image = image;
        self.placeholder.hidden = YES;
    }];
}

- (void)setBadge:(NSString *)badge {
    _badge = [badge copy];
    self.badgeLabel.hidden = badge.length == 0;
    self.badgeLabel.text = badge;
    CGSize size = [badge sizeWithFont:self.badgeLabel.font];
    self.badgeLabel.frame = CGRectMake(4, 4, size.width + 8, 16);
}

- (void)setProgress:(double)progress {
    _progress = progress;
    self.progressTrack.hidden = progress <= 0;
    CGFloat width = self.progressTrack.bounds.size.width;
    self.progressBar.frame = CGRectMake(0, 0, width * (CGFloat)MIN(1, MAX(0, progress)), 3);
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.badge = nil;
    self.progress = 0;
}

@end
