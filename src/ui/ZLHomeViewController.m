#import "ZLHomeViewController.h"
#import "ZLAddonManager.h"
#import "ZLCatalogViewController.h"
#import "ZLEmptyView.h"
#import "ZLImageLoader.h"
#import "ZLLibrary.h"
#import "ZLLibraryRows.h"
#import "ZLRowCell.h"
#import "ZLTheme.h"
#import "ZLTitleViewController.h"

extern NSString *const ZLShowSourcesNotification;

typedef NS_ENUM(NSInteger, ZLHomeFilter) { ZLHomeAll, ZLHomeMovies, ZLHomeSeries, ZLHomeOther };

#pragma mark - Banner

// The featured titles: large pictures that the user swipes, with the name.
@interface ZLBannerView : UIView <UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIPageControl *pages;
@property (nonatomic, copy) NSArray *metas;
@property (nonatomic, copy) void (^onSelect)(ZLMeta *meta);
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation ZLBannerView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = ZLBackgroundColor();
        self.scroll = [[UIScrollView alloc] initWithFrame:self.bounds];
        self.scroll.pagingEnabled = YES;
        self.scroll.showsHorizontalScrollIndicator = NO;
        self.scroll.scrollsToTop = NO;
        self.scroll.delegate = self;
        [self addSubview:self.scroll];
        self.pages = [[UIPageControl alloc] initWithFrame:CGRectMake(0, frame.size.height - 22, frame.size.width, 18)];
        self.pages.currentPageIndicatorTintColor = ZLAccentColor();
        self.pages.userInteractionEnabled = NO;
        [self addSubview:self.pages];
        [self.scroll addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
    }
    return self;
}

- (void)setMetas:(NSArray *)metas {
    if ([metas isEqualToArray:_metas]) return;
    _metas = [metas copy];
    for (UIView *view in self.scroll.subviews) [view removeFromSuperview];
    CGSize size = self.bounds.size;
    for (NSUInteger i = 0; i < metas.count; i++) {
        ZLMeta *meta = metas[i];
        UIView *page = [[UIView alloc] initWithFrame:CGRectMake(size.width * i, 0, size.width, size.height)];
        page.clipsToBounds = YES;
        UIImageView *picture = [[UIImageView alloc] initWithFrame:page.bounds];
        picture.contentMode = UIViewContentModeScaleAspectFill;
        picture.backgroundColor = ZLSurfaceColor();
        [page addSubview:picture];
        NSURL *url = meta.background ?: meta.poster;
        [[ZLImageLoader shared] loadURL:url size:CGSizeMake(size.width, size.height * 1.5) handler:^(UIImage *image) {
            picture.image = image;
        }];
        // A dark shade at the bottom keeps the name readable.
        UIView *shade = [[UIView alloc] initWithFrame:CGRectMake(0, size.height - 70, size.width, 70)];
        shade.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
        [page addSubview:shade];
        UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(14, size.height - 66, size.width - 28, 28)];
        name.text = meta.name;
        name.font = ZLBoldFont(22);
        name.textColor = ZLTextColor();
        name.backgroundColor = [UIColor clearColor];
        [page addSubview:name];
        UILabel *facts = [[UILabel alloc] initWithFrame:CGRectMake(14, size.height - 40, size.width - 28, 16)];
        facts.text = meta.facts;
        facts.font = ZLFont(13);
        facts.textColor = ZLSecondaryTextColor();
        facts.backgroundColor = [UIColor clearColor];
        [page addSubview:facts];
        [self.scroll addSubview:page];
    }
    self.scroll.contentSize = CGSizeMake(size.width * metas.count, size.height);
    self.scroll.contentOffset = CGPointZero;
    self.pages.numberOfPages = (NSInteger)metas.count;
    self.pages.currentPage = 0;
    [self.timer invalidate];
    if (metas.count > 1) {
        self.timer = [NSTimer scheduledTimerWithTimeInterval:7 target:self selector:@selector(advance) userInfo:nil repeats:YES];
    }
}

- (void)advance {
    if (!self.window || self.scroll.tracking) return;
    NSInteger next = (self.pages.currentPage + 1) % MAX(1, self.pages.numberOfPages);
    [self.scroll setContentOffset:CGPointMake(self.bounds.size.width * next, 0) animated:YES];
    self.pages.currentPage = next;
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    self.pages.currentPage = (NSInteger)lround(scrollView.contentOffset.x / MAX(1, self.bounds.size.width));
}

- (void)tapped {
    NSInteger page = (NSInteger)lround(self.scroll.contentOffset.x / MAX(1, self.bounds.size.width));
    if (page >= 0 && page < (NSInteger)self.metas.count && self.onSelect) self.onSelect(self.metas[(NSUInteger)page]);
}

@end

#pragma mark - Home

@interface ZLHomeViewController () <ZLRowCellDelegate>
@property (nonatomic, strong) NSArray *catalogs;
@property (nonatomic, strong) NSMutableDictionary *results;  // catalog key -> metas
@property (nonatomic, strong) NSMutableDictionary *errors;   // catalog key -> text
@property (nonatomic, strong) NSMutableSet *loading;
@property (nonatomic, strong) NSMutableDictionary *offsets;
@property (nonatomic, strong) ZLBannerView *banner;
@property (nonatomic, strong) UISegmentedControl *filter;
@property (nonatomic, strong) ZLEmptyView *emptyView;
@property (nonatomic, strong) NSArray *libraryRows;
@end

@implementation ZLHomeViewController

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        self.title = @"Home";
        self.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Home" image:[UIImage imageNamed:@"Tab-home"] tag:0];
        _results = [NSMutableDictionary dictionary];
        _errors = [NSMutableDictionary dictionary];
        _loading = [NSMutableSet set];
        _offsets = [NSMutableDictionary dictionary];
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(addonsChanged) name:ZLAddonsDidChangeNotification object:nil];
        [center addObserver:self selector:@selector(libraryChanged) name:ZLLibraryDidChangeNotification object:nil];
        [center addObserver:self selector:@selector(libraryChanged) name:ZLNewEpisodesDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = ZLBackgroundColor();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = ZLRowCellHeight;
    [self.tableView registerClass:[ZLRowCell class] forCellReuseIdentifier:@"row"];
    self.filter = [[UISegmentedControl alloc] initWithItems:@[ @"All", @"Films", @"Series", @"Other" ]];
    self.filter.segmentedControlStyle = UISegmentedControlStyleBar;
    self.filter.selectedSegmentIndex = 0;
    [self.filter addTarget:self action:@selector(filterChanged) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.filter;
    self.banner = [[ZLBannerView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 190)];
    __weak ZLHomeViewController *weakSelf = self;
    self.banner.onSelect = ^(ZLMeta *meta) { [weakSelf open:meta]; };
    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
    [self addonsChanged];
}

- (void)refresh {
    [self.results removeAllObjects];
    [self.errors removeAllObjects];
    [[ZLAddonManager shared] reload];
    [self.refreshControl endRefreshing];
}

- (void)filterChanged {
    [self rebuild];
}

- (void)addonsChanged {
    [self rebuild];
    [ZLLibraryRows refreshNewEpisodes];
}

- (void)libraryChanged {
    [self buildLibraryRows];
    [self.tableView reloadData];
}

// Continue watching and New episodes come first, as in ZettaStream.
- (void)buildLibraryRows {
    NSMutableArray *rows = [NSMutableArray array];
    for (ZLLibraryRow *row in @[ [ZLLibraryRows continueWatching], [ZLLibraryRows newEpisodes] ]) {
        if (row.metas.count) [rows addObject:row];
    }
    self.libraryRows = rows;
}

- (BOOL)catalogMatchesFilter:(ZLCatalog *)catalog {
    switch ((ZLHomeFilter)self.filter.selectedSegmentIndex) {
        case ZLHomeAll: return YES;
        case ZLHomeMovies: return [catalog.type isEqualToString:@"movie"];
        case ZLHomeSeries: return [catalog.type isEqualToString:@"series"];
        case ZLHomeOther: return ![catalog.type isEqualToString:@"movie"] && ![catalog.type isEqualToString:@"series"];
    }
    return YES;
}

- (void)rebuild {
    NSMutableArray *catalogs = [NSMutableArray array];
    for (ZLCatalog *catalog in [[ZLAddonManager shared] homeCatalogs]) {
        if ([self catalogMatchesFilter:catalog]) [catalogs addObject:catalog];
    }
    self.catalogs = catalogs;
    [self buildLibraryRows];
    BOOL empty = [ZLAddonManager shared].addons.count == 0;
    if (empty && !self.emptyView) {
        self.emptyView = [[ZLEmptyView alloc] initWithTitle:@"No sources"
                                                       text:@"ZettaLite comes with no sources. Add the link of a Stremio addon or of an IPTV playlist in Settings."
                                                     button:@"Add a source in Settings"
                                                     target:self action:@selector(showSources)];
        self.emptyView.frame = self.tableView.bounds;
    }
    self.tableView.backgroundView = empty ? self.emptyView : nil;
    self.tableView.tableHeaderView = empty ? nil : self.banner;
    [self.tableView reloadData];
    [self updateBanner];
}

- (void)showSources {
    [[NSNotificationCenter defaultCenter] postNotificationName:ZLShowSourcesNotification object:self];
}

// The banner shows the first titles with a large picture.
- (void)updateBanner {
    NSMutableArray *featured = [NSMutableArray array];
    for (ZLCatalog *catalog in self.catalogs) {
        for (ZLMeta *meta in self.results[catalog.key]) {
            if (meta.background && featured.count < 6) [featured addObject:meta];
        }
        if (featured.count >= 6) break;
    }
    self.banner.metas = featured;
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return [ZLAddonManager shared].addons.count ? (NSInteger)self.libraryRows.count : 0;
    return (NSInteger)self.catalogs.count;
}

- (NSString *)titleFor:(ZLCatalog *)catalog {
    NSString *type = [catalog.type isEqualToString:@"movie"] ? @"Films" : [catalog.type isEqualToString:@"series"] ? @"Series" : catalog.type.capitalizedString;
    if ([catalog.name rangeOfString:type options:NSCaseInsensitiveSearch].location != NSNotFound) return catalog.name;
    return [NSString stringWithFormat:@"%@ %@", catalog.name, type];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ZLRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row" forIndexPath:indexPath];
    if (indexPath.section == 0) {
        ZLLibraryRow *row = self.libraryRows[(NSUInteger)indexPath.row];
        cell.delegate = self;
        cell.tag = -1 - indexPath.row;
        cell.showsMore = NO;
        cell.title = row.title;
        cell.subtitle = nil;
        cell.badges = row.badges;
        cell.progress = row.progress;
        cell.metas = row.metas;
        cell.loading = NO;
        cell.offset = 0;
        return cell;
    }
    cell.badges = nil;
    cell.progress = nil;
    ZLCatalog *catalog = self.catalogs[(NSUInteger)indexPath.row];
    cell.delegate = self;
    cell.showsMore = YES;
    cell.title = [self titleFor:catalog];
    cell.subtitle = catalog.addon.name;
    cell.metas = self.results[catalog.key];
    cell.message = self.errors[catalog.key] ?: @"This catalog is empty.";
    cell.loading = self.results[catalog.key] == nil && !self.errors[catalog.key];
    cell.offset = [self.offsets[catalog.key] floatValue];
    cell.tag = indexPath.row;
    [self loadCatalog:catalog];
    return cell;
}

- (void)tableView:(UITableView *)tableView didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1 && (NSUInteger)indexPath.row < self.catalogs.count) {
        ZLCatalog *catalog = self.catalogs[(NSUInteger)indexPath.row];
        self.offsets[catalog.key] = @(((ZLRowCell *)cell).offset);
    }
}

- (void)loadCatalog:(ZLCatalog *)catalog {
    NSString *key = catalog.key;
    if (self.results[key] || self.errors[key] || [self.loading containsObject:key]) return;
    [self.loading addObject:key];
    [[ZLAddonManager shared] loadCatalog:catalog extras:nil completion:^(NSArray *metas, NSError *error) {
        [self.loading removeObject:key];
        if (error && !metas.count) self.errors[key] = [NSString stringWithFormat:@"The catalog did not load. %@", error.localizedDescription];
        else self.results[key] = metas;
        NSUInteger row = [self.catalogs indexOfObject:catalog];
        if (row != NSNotFound) {
            [self.tableView reloadRowsAtIndexPaths:@[ [NSIndexPath indexPathForRow:(NSInteger)row inSection:1] ]
                                  withRowAnimation:UITableViewRowAnimationNone];
        }
        [self updateBanner];
    }];
}

#pragma mark - Rows

- (void)rowCell:(ZLRowCell *)cell didSelectMeta:(ZLMeta *)meta atIndex:(NSUInteger)index {
    if (cell.tag < 0) {
        // A library row plays the next episode, or the film, at once.
        ZLLibraryRow *row = self.libraryRows[(NSUInteger)(-1 - cell.tag)];
        ZLTitleViewController *page = [[ZLTitleViewController alloc] initWithMeta:meta];
        [self.navigationController pushViewController:page animated:YES];
        id episode = index < row.episodes.count ? row.episodes[index] : nil;
        [page playEpisode:[episode isKindOfClass:[ZLEpisode class]] ? episode : nil];
        return;
    }
    [self open:meta];
}

- (void)rowCellDidSelectTitle:(ZLRowCell *)cell {
    if (cell.tag < 0 || (NSUInteger)cell.tag >= self.catalogs.count) return;
    ZLCatalog *catalog = self.catalogs[(NSUInteger)cell.tag];
    ZLCatalogViewController *grid = [[ZLCatalogViewController alloc] initWithCatalog:catalog extras:nil];
    grid.title = [self titleFor:catalog];
    [self.navigationController pushViewController:grid animated:YES];
}

- (void)open:(ZLMeta *)meta {
    [self.navigationController pushViewController:[[ZLTitleViewController alloc] initWithMeta:meta] animated:YES];
}

@end
