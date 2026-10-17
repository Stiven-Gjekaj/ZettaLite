#import "ZLLiveViewController.h"
#import "ZLChannels.h"
#import "ZLEmptyView.h"
#import "ZLImageLoader.h"
#import "ZLPlayback.h"
#import "ZLSources.h"
#import "ZLTheme.h"

extern NSString *const ZLShowSourcesNotification;

static const CGFloat ZLLogoSize = 36;

@interface ZLLiveViewController () <UISearchBarDelegate>
@property (nonatomic, copy) NSString *group;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, copy) NSString *query;
// For the first screen: the favourites and the groups. For a group, or for a
// search: the channels.
@property (nonatomic, strong) NSArray *favourites;
@property (nonatomic, strong) NSArray *groups;
@property (nonatomic, strong) NSArray *channels;
// A link that waits for the channels to load.
@property (nonatomic, copy) void (^pendingLink)(void);
@end

@implementation ZLLiveViewController

- (instancetype)init {
    return [self initWithGroup:nil];
}

- (instancetype)initWithGroup:(NSString *)group {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _group = [group copy];
        self.title = group ?: @"Live TV";
        if (!group) self.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Live TV" image:[UIImage imageNamed:@"Tab-live"] tag:3];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload)
                                                     name:ZLChannelsDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = ZLBackgroundColor();
    self.tableView.separatorColor = [UIColor colorWithWhite:0.15 alpha:1];
    self.tableView.rowHeight = 52;
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    self.searchBar.placeholder = self.group ? @"Find a channel in this group" : @"Find a channel";
    self.searchBar.delegate = self;
    self.searchBar.tintColor = [UIColor colorWithWhite:0.07 alpha:1];
    self.tableView.tableHeaderView = self.searchBar;
    if (!self.group) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                               target:self action:@selector(refresh)];
        ZLChannelList *list = [ZLChannelList shared];
        if (!list.channels.count && !list.loading) [list reload];
    }
    [self reload];
}

- (void)refresh {
    [[ZLChannelList shared] reload];
}

- (BOOL)showsChannels {
    return self.group || self.query.length;
}

- (void)reload {
    if (self.pendingLink && ![ZLChannelList shared].loading) {
        void (^pending)(void) = self.pendingLink;
        self.pendingLink = nil;
        dispatch_async(dispatch_get_main_queue(), pending);
    }
    ZLChannelList *list = [ZLChannelList shared];
    NSArray *channels = self.group ? [list channelsInGroup:self.group] : list.channels;
    if (self.query.length) {
        NSMutableArray *matching = [NSMutableArray array];
        for (ZLChannel *channel in channels) {
            if ([channel.name rangeOfString:self.query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound) {
                [matching addObject:channel];
            }
        }
        channels = matching;
    }
    self.channels = channels;
    self.favourites = [list favourites];
    self.groups = [list groups];
    [self updateEmptyView];
    [self.tableView reloadData];
}

- (void)updateEmptyView {
    ZLChannelList *list = [ZLChannelList shared];
    ZLEmptyView *empty = nil;
    if (!list.channels.count) {
        BOOL hasSources = [[ZLSourceList shared] sourcesOfKind:ZLSourcePlaylist].count ||
                          [[ZLSourceList shared] sourcesOfKind:ZLSourceLink].count;
        if (list.loading) {
            empty = [[ZLEmptyView alloc] initWithTitle:@"" text:@"Loading the channels." button:nil target:nil action:NULL];
        } else if (!hasSources) {
            empty = [[ZLEmptyView alloc] initWithTitle:@"No channels"
                                                  text:@"Add an M3U playlist or a media link in Sources. The channels show here."
                                                button:@"Open Sources" target:self action:@selector(showSources)];
        } else {
            NSString *text = list.failures.count ? [list.failures componentsJoinedByString:@"\n"] : @"The playlists have no channels.";
            empty = [[ZLEmptyView alloc] initWithTitle:@"No channels" text:text button:@"Try again" target:self action:@selector(refresh)];
        }
    } else if (self.showsChannels && !self.channels.count) {
        empty = [[ZLEmptyView alloc] initWithTitle:@"" text:@"No channel has this name." button:nil target:nil action:NULL];
    }
    if (empty) empty.frame = self.tableView.bounds;
    self.tableView.backgroundView = empty;
    self.searchBar.hidden = !list.channels.count;
}

- (void)whenLoaded:(void (^)(void))block {
    ZLChannelList *list = [ZLChannelList shared];
    if (!list.channels.count && !list.loading) [list reload];
    if (list.loading) self.pendingLink = block;
    else block();
}

- (void)openGroup:(NSString *)group {
    __weak ZLLiveViewController *weakSelf = self;
    [self whenLoaded:^{
        if (![[[ZLChannelList shared] groups] containsObject:group]) return;
        [weakSelf.navigationController pushViewController:[[ZLLiveViewController alloc] initWithGroup:group] animated:NO];
    }];
}

- (void)playChannelNamed:(NSString *)name {
    __weak ZLLiveViewController *weakSelf = self;
    [self whenLoaded:^{
        for (ZLChannel *channel in [ZLChannelList shared].channels) {
            if ([channel.name caseInsensitiveCompare:name] != NSOrderedSame) continue;
            [weakSelf playChannel:channel];
            return;
        }
    }];
}

- (void)playChannel:(ZLChannel *)channel {
    ZLPlayItem *play = [ZLPlayItem itemWithURL:channel.URL title:channel.name];
    play.headers = channel.headers;
    play.sourceName = channel.group;
    // After a pop with no animation, this view is not in the window yet. The
    // navigation controller is.
    [ZLPlayback play:play from:self.navigationController ?: self];
}

- (void)showSources {
    [[NSNotificationCenter defaultCenter] postNotificationName:ZLShowSourcesNotification object:self];
}

#pragma mark - Search

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
    self.query = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    [self reload];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [self.searchBar resignFirstResponder];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.showsChannels ? 1 : 2;
}

- (NSArray *)itemsInSection:(NSInteger)section {
    if (self.showsChannels) return self.channels;
    return section == 0 ? self.favourites : self.groups;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[self itemsInSection:section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.showsChannels || ![self itemsInSection:section].count) return nil;
    return section == 0 ? @"Favourites" : @"Groups";
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title = [self tableView:tableView titleForHeaderInSection:section];
    if (!title) return nil;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 30)];
    header.backgroundColor = ZLBackgroundColor();
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(header.bounds, 10, 0)];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = ZLAccentColor();
    label.font = ZLBoldFont(13);
    label.text = title.uppercaseString;
    [header addSubview:label];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return [self tableView:tableView titleForHeaderInSection:section] ? 30 : 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    id item = [self itemsInSection:indexPath.section][(NSUInteger)indexPath.row];
    if ([item isKindOfClass:[NSString class]]) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"group"] ?:
            [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"group"];
        cell.backgroundColor = ZLBackgroundColor();
        cell.textLabel.textColor = ZLTextColor();
        cell.textLabel.font = ZLBoldFont(16);
        cell.detailTextLabel.textColor = ZLSecondaryTextColor();
        cell.detailTextLabel.font = ZLFont(14);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.textLabel.text = item;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)[[ZLChannelList shared] channelsInGroup:item].count];
        return cell;
    }
    return [self channelCell:item tableView:tableView indexPath:indexPath];
}

- (UITableViewCell *)channelCell:(ZLChannel *)channel tableView:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"channel"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"channel"];
        cell.backgroundColor = ZLBackgroundColor();
        cell.textLabel.textColor = ZLTextColor();
        cell.textLabel.font = ZLBoldFont(16);
        cell.detailTextLabel.textColor = ZLSecondaryTextColor();
        cell.detailTextLabel.font = ZLFont(13);
        UIButton *star = [UIButton buttonWithType:UIButtonTypeCustom];
        star.frame = CGRectMake(0, 0, 44, 44);
        star.titleLabel.font = [UIFont systemFontOfSize:22];
        [star setTitleColor:ZLSecondaryTextColor() forState:UIControlStateNormal];
        [star setTitleColor:ZLAccentColor() forState:UIControlStateSelected];
        [star setTitle:@"☆" forState:UIControlStateNormal];
        [star setTitle:@"★" forState:UIControlStateSelected];
        [star addTarget:self action:@selector(toggleFavourite:event:) forControlEvents:UIControlEventTouchUpInside];
        cell.accessoryView = star;
    }
    cell.textLabel.text = channel.name;
    // In a group the name of the group says nothing new.
    cell.detailTextLabel.text = self.group ? channel.URL.host : (channel.group ?: channel.URL.host);
    ((UIButton *)cell.accessoryView).selected = [[ZLChannelList shared] isFavourite:channel];
    [self setLogoOf:cell channel:channel];
    return cell;
}

- (UIImage *)blankLogo {
    static UIImage *blank;
    if (!blank) {
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(ZLLogoSize, ZLLogoSize), NO, 0);
        [ZLSurfaceColor() setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, ZLLogoSize, ZLLogoSize) cornerRadius:4] fill];
        blank = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    return blank;
}

- (void)setLogoOf:(UITableViewCell *)cell channel:(ZLChannel *)channel {
    CGSize size = CGSizeMake(ZLLogoSize, ZLLogoSize);
    ZLImageLoader *loader = [ZLImageLoader shared];
    UIImage *cached = channel.logo ? [loader cachedImageForURL:channel.logo size:size] : nil;
    cell.imageView.image = cached ?: [self blankLogo];
    if (cached || !channel.logo) return;
    NSString *key = channel.key;
    __weak UITableViewCell *weakCell = cell;
    __weak ZLLiveViewController *weakSelf = self;
    [loader loadURL:channel.logo size:size handler:^(UIImage *image) {
        UITableViewCell *strongCell = weakCell;
        NSIndexPath *path = [weakSelf.tableView indexPathForCell:strongCell];
        id item = path ? [weakSelf itemsInSection:path.section][(NSUInteger)path.row] : nil;
        if (!image || ![item isKindOfClass:[ZLChannel class]] || ![[item key] isEqualToString:key]) return;
        strongCell.imageView.image = [weakSelf logoImage:image];
        [strongCell setNeedsLayout];
    }];
}

// Fits a logo into a square of the logo size, so that the names line up.
- (UIImage *)logoImage:(UIImage *)image {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(ZLLogoSize, ZLLogoSize), NO, 0);
    CGFloat scale = MIN(ZLLogoSize / MAX(image.size.width, 1), ZLLogoSize / MAX(image.size.height, 1));
    CGSize size = CGSizeMake(image.size.width * scale, image.size.height * scale);
    [image drawInRect:CGRectMake((ZLLogoSize - size.width) / 2, (ZLLogoSize - size.height) / 2, size.width, size.height)];
    UIImage *fitted = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return fitted;
}

- (void)toggleFavourite:(UIButton *)star event:(UIEvent *)event {
    CGPoint point = [[[event allTouches] anyObject] locationInView:self.tableView];
    NSIndexPath *path = [self.tableView indexPathForRowAtPoint:point];
    id item = path ? [self itemsInSection:path.section][(NSUInteger)path.row] : nil;
    if (![item isKindOfClass:[ZLChannel class]]) return;
    ZLChannelList *list = [ZLChannelList shared];
    [list setChannel:item favourite:![list isFavourite:item]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    id item = [self itemsInSection:indexPath.section][(NSUInteger)indexPath.row];
    if ([item isKindOfClass:[NSString class]]) {
        [self.navigationController pushViewController:[[ZLLiveViewController alloc] initWithGroup:item] animated:YES];
        return;
    }
    [self playChannel:item];
}

@end
