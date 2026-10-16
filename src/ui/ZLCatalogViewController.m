#import "ZLCatalogViewController.h"
#import "ZLAddonManager.h"
#import "ZLPosterCell.h"
#import "ZLTheme.h"
#import "ZLTitleViewController.h"

@interface ZLCatalogViewController () <UIActionSheetDelegate>
@property (nonatomic, strong) ZLCatalog *catalog;
@property (nonatomic, copy) NSDictionary *extras;
@property (nonatomic, strong) NSMutableArray *metas;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL finished;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation ZLCatalogViewController

- (instancetype)initWithCatalog:(ZLCatalog *)catalog extras:(NSDictionary *)extras {
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.itemSize = ZLPosterCellSize;
    layout.minimumInteritemSpacing = 8;
    layout.minimumLineSpacing = 10;
    layout.sectionInset = UIEdgeInsetsMake(12, 10, 12, 10);
    if ((self = [super initWithCollectionViewLayout:layout])) {
        _catalog = catalog;
        _extras = [extras copy];
        _metas = [NSMutableArray array];
        self.title = catalog.name;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.collectionView.backgroundColor = ZLBackgroundColor();
    [self.collectionView registerClass:[ZLPosterCell class] forCellWithReuseIdentifier:@"poster"];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];
    if ([self.catalog extraNamed:@"genre"].options.count) {
        self.navigationItem.rightBarButtonItems = @[
            [[UIBarButtonItem alloc] initWithCustomView:self.spinner],
            [[UIBarButtonItem alloc] initWithTitle:@"Genre" style:UIBarButtonItemStyleBordered target:self action:@selector(chooseGenre)],
        ];
    }
    [self loadMore];
}

- (void)chooseGenre {
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Genre" delegate:self cancelButtonTitle:nil
                                         destructiveButtonTitle:nil otherButtonTitles:@"All", nil];
    for (NSString *genre in [self.catalog extraNamed:@"genre"].options) [sheet addButtonWithTitle:genre];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
    [sheet showFromTabBar:self.tabBarController.tabBar];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    if (index == sheet.cancelButtonIndex) return;
    NSMutableDictionary *extras = [self.extras mutableCopy] ?: [NSMutableDictionary dictionary];
    if (index == 0) [extras removeObjectForKey:@"genre"];
    else extras[@"genre"] = [sheet buttonTitleAtIndex:index];
    self.extras = extras;
    self.title = index == 0 ? self.catalog.name : [sheet buttonTitleAtIndex:index];
    [self.metas removeAllObjects];
    self.finished = NO;
    [self.collectionView reloadData];
    [self loadMore];
}

- (void)loadMore {
    if (self.loading || self.finished) return;
    self.loading = YES;
    [self.spinner startAnimating];
    NSMutableDictionary *extras = [self.extras mutableCopy] ?: [NSMutableDictionary dictionary];
    if (self.metas.count) extras[@"skip"] = [NSString stringWithFormat:@"%lu", (unsigned long)self.metas.count];
    NSDictionary *asked = self.extras;
    [[ZLAddonManager shared] loadCatalog:self.catalog extras:extras completion:^(NSArray *metas, NSError *error) {
        if (asked != self.extras && ![asked isEqual:self.extras]) return;
        self.loading = NO;
        [self.spinner stopAnimating];
        // An addon with no pages gives the same titles again.
        NSMutableSet *known = [NSMutableSet set];
        for (ZLMeta *meta in self.metas) [known addObject:meta.identifier];
        NSMutableArray *added = [NSMutableArray array];
        for (ZLMeta *meta in metas) {
            if (![known containsObject:meta.identifier]) [added addObject:meta];
        }
        if (!added.count) {
            self.finished = YES;
            return;
        }
        [self.metas addObjectsFromArray:added];
        [self.collectionView reloadData];
    }];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)self.metas.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ZLPosterCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"poster" forIndexPath:indexPath];
    cell.meta = self.metas[(NSUInteger)indexPath.item];
    if ((NSUInteger)indexPath.item + 9 >= self.metas.count) [self loadMore];
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    ZLMeta *meta = self.metas[(NSUInteger)indexPath.item];
    [self.navigationController pushViewController:[[ZLTitleViewController alloc] initWithMeta:meta] animated:YES];
}

@end
