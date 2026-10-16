#import "ZLRowCell.h"
#import "ZLPosterCell.h"
#import "ZLTheme.h"

const CGFloat ZLRowCellHeight = 228;

@interface ZLRowCell () <UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, strong) UIButton *titleButton;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UICollectionView *collection;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *messageLabel;
@end

@implementation ZLRowCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = ZLBackgroundColor();
        self.contentView.backgroundColor = ZLBackgroundColor();
        self.titleButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.titleButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        self.titleButton.titleLabel.font = ZLBoldFont(18);
        [self.titleButton setTitleColor:ZLTextColor() forState:UIControlStateNormal];
        [self.titleButton setTitleColor:ZLAccentColor() forState:UIControlStateHighlighted];
        [self.titleButton addTarget:self action:@selector(titleTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:self.titleButton];
        self.subtitleLabel = [UILabel new];
        self.subtitleLabel.font = ZLFont(12);
        self.subtitleLabel.textColor = ZLSecondaryTextColor();
        self.subtitleLabel.backgroundColor = [UIColor clearColor];
        self.subtitleLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:self.subtitleLabel];
        UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
        layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        layout.itemSize = ZLPosterCellSize;
        layout.minimumLineSpacing = 10;
        layout.sectionInset = UIEdgeInsetsMake(0, 12, 0, 12);
        self.collection = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
        self.collection.backgroundColor = ZLBackgroundColor();
        self.collection.showsHorizontalScrollIndicator = NO;
        self.collection.dataSource = self;
        self.collection.delegate = self;
        self.collection.scrollsToTop = NO;
        [self.collection registerClass:[ZLPosterCell class] forCellWithReuseIdentifier:@"poster"];
        [self.contentView addSubview:self.collection];
        self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
        self.spinner.hidesWhenStopped = YES;
        [self.contentView addSubview:self.spinner];
        self.messageLabel = [UILabel new];
        self.messageLabel.font = ZLFont(13);
        self.messageLabel.textColor = ZLSecondaryTextColor();
        self.messageLabel.backgroundColor = [UIColor clearColor];
        self.messageLabel.numberOfLines = 2;
        [self.contentView addSubview:self.messageLabel];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    self.titleButton.frame = CGRectMake(12, 6, width * 0.7, 26);
    self.subtitleLabel.frame = CGRectMake(width * 0.7, 10, width * 0.3 - 12, 20);
    self.collection.frame = CGRectMake(0, 36, width, ZLPosterCellSize.height);
    self.spinner.center = CGPointMake(width / 2, 36 + ZLPosterCellSize.height / 2);
    self.messageLabel.frame = CGRectMake(12, 36, width - 24, 60);
}

- (void)setTitle:(NSString *)title {
    _title = [title copy];
    NSString *text = self.showsMore ? [title stringByAppendingString:@"  >"] : title;
    [self.titleButton setTitle:text forState:UIControlStateNormal];
}

- (void)setShowsMore:(BOOL)showsMore {
    _showsMore = showsMore;
    self.title = self.title;
}

- (void)setSubtitle:(NSString *)subtitle {
    _subtitle = [subtitle copy];
    self.subtitleLabel.text = subtitle;
}

- (void)setMetas:(NSArray *)metas {
    _metas = [metas copy];
    [self.collection reloadData];
    [self updateState];
}

- (void)setLoading:(BOOL)loading {
    _loading = loading;
    [self updateState];
}

- (void)setMessage:(NSString *)message {
    _message = [message copy];
    [self updateState];
}

- (void)updateState {
    if (self.loading && !self.metas.count) [self.spinner startAnimating];
    else [self.spinner stopAnimating];
    self.messageLabel.hidden = self.loading || self.metas.count;
    self.messageLabel.text = self.message;
}

- (CGFloat)offset {
    return self.collection.contentOffset.x;
}

- (void)setOffset:(CGFloat)offset {
    [self.collection layoutIfNeeded];
    CGFloat maximum = MAX(0, self.collection.contentSize.width - self.collection.bounds.size.width);
    self.collection.contentOffset = CGPointMake(MIN(offset, maximum), 0);
}

- (void)titleTapped {
    if (self.showsMore) [self.delegate rowCellDidSelectTitle:self];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)self.metas.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ZLPosterCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"poster" forIndexPath:indexPath];
    NSUInteger index = (NSUInteger)indexPath.item;
    cell.meta = self.metas[index];
    id badge = index < self.badges.count ? self.badges[index] : nil;
    cell.badge = [badge isKindOfClass:[NSString class]] ? badge : nil;
    cell.progress = index < self.progress.count ? [self.progress[index] doubleValue] : 0;
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];
    NSUInteger index = (NSUInteger)indexPath.item;
    [self.delegate rowCell:self didSelectMeta:self.metas[index] atIndex:index];
}

@end
