#import "ZLLibraryViewController.h"
#import "ZLEmptyView.h"
#import "ZLLibrary.h"
#import "ZLLibraryRows.h"
#import "ZLRowCell.h"
#import "ZLTheme.h"
#import "ZLTitleViewController.h"

@interface ZLLibraryViewController () <ZLRowCellDelegate>
@property (nonatomic, strong) NSArray *rows;
@end

@implementation ZLLibraryViewController

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        self.title = @"Library";
        self.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Library" image:[UIImage imageNamed:@"Tab-library"] tag:2];
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(reload) name:ZLLibraryDidChangeNotification object:nil];
        [center addObserver:self selector:@selector(reload) name:ZLNewEpisodesDidChangeNotification object:nil];
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
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [ZLLibraryRows refreshNewEpisodes];
}

- (void)reload {
    NSMutableArray *rows = [NSMutableArray array];
    for (ZLLibraryRow *row in @[ [ZLLibraryRows continueWatching], [ZLLibraryRows newEpisodes], [ZLLibraryRows watchlist] ]) {
        if (row.metas.count) [rows addObject:row];
    }
    self.rows = rows;
    if (!rows.count) {
        ZLEmptyView *empty = [[ZLEmptyView alloc] initWithTitle:@"Your library"
                                                           text:@"The titles that you watch, and the titles that you add with + List, show here."
                                                         button:nil target:nil action:NULL];
        empty.frame = self.tableView.bounds;
        self.tableView.backgroundView = empty;
    } else {
        self.tableView.backgroundView = nil;
    }
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ZLRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row" forIndexPath:indexPath];
    ZLLibraryRow *row = self.rows[(NSUInteger)indexPath.row];
    cell.delegate = self;
    cell.tag = indexPath.row;
    cell.title = row.title;
    cell.subtitle = [NSString stringWithFormat:@"%lu", (unsigned long)row.metas.count];
    cell.badges = row.badges;
    cell.progress = row.progress;
    cell.metas = row.metas;
    return cell;
}

- (void)rowCell:(ZLRowCell *)cell didSelectMeta:(ZLMeta *)meta atIndex:(NSUInteger)index {
    ZLLibraryRow *row = (NSUInteger)cell.tag < self.rows.count ? self.rows[(NSUInteger)cell.tag] : nil;
    ZLTitleViewController *page = [[ZLTitleViewController alloc] initWithMeta:meta];
    [self.navigationController pushViewController:page animated:YES];
    // A tap on continue watching or a new episode plays it at once.
    id episode = index < row.episodes.count ? row.episodes[index] : nil;
    if (row.episodes) [page playEpisode:[episode isKindOfClass:[ZLEpisode class]] ? episode : nil];
}

- (void)rowCellDidSelectTitle:(ZLRowCell *)cell {
}

@end
