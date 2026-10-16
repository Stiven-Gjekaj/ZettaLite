#import "ZLSearchViewController.h"
#import "ZLAddonManager.h"
#import "ZLCatalogViewController.h"
#import "ZLEmptyView.h"
#import "ZLRowCell.h"
#import "ZLTheme.h"
#import "ZLTitleViewController.h"

@interface ZLSearchViewController () <UISearchBarDelegate, ZLRowCellDelegate>
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSMutableArray *rows;  // Dictionaries with catalog and metas.
@property (nonatomic) NSUInteger generation;
@property (nonatomic) BOOL searching;
@property (nonatomic, copy) NSString *query;
@end

@implementation ZLSearchViewController

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        self.title = @"Search";
        self.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Search" image:[UIImage imageNamed:@"Tab-search"] tag:1];
        _rows = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = ZLBackgroundColor();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = ZLRowCellHeight;
    [self.tableView registerClass:[ZLRowCell class] forCellReuseIdentifier:@"row"];
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    self.searchBar.placeholder = @"Films, series, and more";
    self.searchBar.delegate = self;
    self.searchBar.tintColor = [UIColor colorWithWhite:0.07 alpha:1];
    self.tableView.tableHeaderView = self.searchBar;
    [self updateEmpty];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.query.length) [self.searchBar becomeFirstResponder];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    [self searchFor:searchBar.text];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [self.searchBar resignFirstResponder];
}

- (void)searchFor:(NSString *)text {
    NSString *query = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (!query.length) return;
    self.searchBar.text = query;
    self.query = query;
    NSUInteger generation = ++self.generation;
    [self.rows removeAllObjects];
    self.searching = YES;
    [self.tableView reloadData];
    [self updateEmpty];
    [[ZLAddonManager shared] search:query each:^(ZLCatalog *catalog, NSArray *metas) {
        if (generation != self.generation) return;
        [self.rows addObject:@{ @"catalog": catalog, @"metas": metas }];
        [self.tableView reloadData];
        [self updateEmpty];
    } done:^{
        if (generation != self.generation) return;
        self.searching = NO;
        [self updateEmpty];
    }];
}

- (void)updateEmpty {
    NSString *text = nil;
    if (![ZLAddonManager shared].addons.count) text = @"Add a Stremio addon in Settings. Then search here.";
    else if (!self.query.length) text = @"Type the name of a film or a series.";
    else if (self.searching && !self.rows.count) text = @"The addons search.";
    else if (!self.rows.count) text = [NSString stringWithFormat:@"No addon found \"%@\".", self.query];
    if (!text) {
        self.tableView.backgroundView = nil;
        return;
    }
    ZLEmptyView *empty = [[ZLEmptyView alloc] initWithTitle:@"" text:text button:nil target:nil action:NULL];
    empty.frame = self.tableView.bounds;
    self.tableView.backgroundView = empty;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ZLRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row" forIndexPath:indexPath];
    NSDictionary *row = self.rows[(NSUInteger)indexPath.row];
    ZLCatalog *catalog = row[@"catalog"];
    cell.delegate = self;
    cell.tag = indexPath.row;
    cell.showsMore = YES;
    NSString *type = [catalog.type isEqualToString:@"movie"] ? @"Films" : [catalog.type isEqualToString:@"series"] ? @"Series" : catalog.type.capitalizedString;
    cell.title = type;
    cell.subtitle = catalog.addon.name;
    cell.metas = row[@"metas"];
    cell.offset = 0;
    return cell;
}

- (void)rowCell:(ZLRowCell *)cell didSelectMeta:(ZLMeta *)meta atIndex:(NSUInteger)index {
    [self.navigationController pushViewController:[[ZLTitleViewController alloc] initWithMeta:meta] animated:YES];
}

- (void)rowCellDidSelectTitle:(ZLRowCell *)cell {
    if ((NSUInteger)cell.tag >= self.rows.count) return;
    ZLCatalog *catalog = self.rows[(NSUInteger)cell.tag][@"catalog"];
    ZLCatalogViewController *grid = [[ZLCatalogViewController alloc] initWithCatalog:catalog extras:@{ @"search": self.query }];
    grid.title = self.query;
    [self.navigationController pushViewController:grid animated:YES];
}

@end
