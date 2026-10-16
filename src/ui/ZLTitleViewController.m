#import "ZLTitleViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "ZLAddonManager.h"
#import "ZLCatalogViewController.h"
#import "ZLImageLoader.h"
#import "ZLRowCell.h"
#import "ZLPlayback.h"
#import "ZLSettings.h"
#import "ZLStreamRank.h"
#import "ZLStreamsViewController.h"
#import "ZLTheme.h"

typedef NS_ENUM(NSInteger, ZLTitleSection) { ZLTitleAbout, ZLTitleEpisodes, ZLTitleMore, ZLTitleSectionCount };

#pragma mark - Header

@interface ZLTitleHeader : UIView
@property (nonatomic, strong) UIImageView *backdrop;
@property (nonatomic, strong) UIImageView *poster;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *factsLabel;
@property (nonatomic, strong) UILabel *genresLabel;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *listButton;
@property (nonatomic, strong) UIButton *sourcesButton;
@end

@implementation ZLTitleHeader

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        CGFloat width = frame.size.width;
        self.backgroundColor = ZLBackgroundColor();
        self.backdrop = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, width, width * 9 / 16)];
        self.backdrop.contentMode = UIViewContentModeScaleAspectFill;
        self.backdrop.clipsToBounds = YES;
        self.backdrop.backgroundColor = ZLSurfaceColor();
        [self addSubview:self.backdrop];
        UIView *shade = [[UIView alloc] initWithFrame:CGRectMake(0, width * 9 / 16 - 60, width, 60)];
        CAGradientLayer *gradient = [CAGradientLayer layer];
        gradient.frame = shade.bounds;
        gradient.colors = @[ (id)[UIColor colorWithWhite:0 alpha:0].CGColor, (id)[UIColor blackColor].CGColor ];
        [shade.layer addSublayer:gradient];
        [self addSubview:shade];
        self.poster = [[UIImageView alloc] initWithFrame:CGRectMake(12, width * 9 / 16 - 70, 90, 135)];
        self.poster.contentMode = UIViewContentModeScaleAspectFill;
        self.poster.clipsToBounds = YES;
        self.poster.backgroundColor = ZLSurfaceColor();
        self.poster.layer.cornerRadius = 4;
        self.poster.layer.borderWidth = 1;
        self.poster.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.2].CGColor;
        [self addSubview:self.poster];
        CGFloat x = 112;
        self.nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(x, width * 9 / 16 - 8, width - x - 10, 48)];
        self.nameLabel.font = ZLBoldFont(20);
        self.nameLabel.textColor = ZLTextColor();
        self.nameLabel.backgroundColor = [UIColor clearColor];
        self.nameLabel.numberOfLines = 2;
        self.nameLabel.adjustsFontSizeToFitWidth = YES;
        [self addSubview:self.nameLabel];
        self.factsLabel = [[UILabel alloc] initWithFrame:CGRectMake(x, width * 9 / 16 + 40, width - x - 10, 16)];
        self.factsLabel.font = ZLFont(13);
        self.factsLabel.textColor = ZLSecondaryTextColor();
        self.factsLabel.backgroundColor = [UIColor clearColor];
        [self addSubview:self.factsLabel];
        self.genresLabel = [[UILabel alloc] initWithFrame:CGRectMake(x, width * 9 / 16 + 56, width - x - 10, 16)];
        self.genresLabel.font = ZLFont(12);
        self.genresLabel.textColor = ZLSecondaryTextColor();
        self.genresLabel.backgroundColor = [UIColor clearColor];
        [self addSubview:self.genresLabel];
        CGFloat buttons = width * 9 / 16 + 76;
        self.playButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.playButton.frame = CGRectMake(12, buttons, width - 24 - 84 - 84 - 16, 42);
        self.playButton.backgroundColor = ZLAccentColor();
        self.playButton.layer.cornerRadius = 6;
        self.playButton.titleLabel.font = ZLBoldFont(17);
        [self.playButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        [self.playButton setTitle:@"Play" forState:UIControlStateNormal];
        [self addSubview:self.playButton];
        self.sourcesButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.sourcesButton.frame = CGRectMake(width - 12 - 84 - 8 - 84, buttons, 84, 42);
        self.sourcesButton.layer.cornerRadius = 6;
        self.sourcesButton.layer.borderWidth = 1;
        self.sourcesButton.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.4].CGColor;
        self.sourcesButton.titleLabel.font = ZLBoldFont(14);
        [self.sourcesButton setTitleColor:ZLTextColor() forState:UIControlStateNormal];
        [self.sourcesButton setTitle:@"Sources" forState:UIControlStateNormal];
        [self addSubview:self.sourcesButton];
        self.listButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.listButton.frame = CGRectMake(width - 12 - 84, buttons, 84, 42);
        self.listButton.layer.cornerRadius = 6;
        self.listButton.layer.borderWidth = 1;
        self.listButton.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.4].CGColor;
        self.listButton.titleLabel.font = ZLBoldFont(14);
        [self.listButton setTitleColor:ZLTextColor() forState:UIControlStateNormal];
        [self.listButton setTitle:@"+ List" forState:UIControlStateNormal];
        [self addSubview:self.listButton];
    }
    return self;
}

+ (CGFloat)heightForWidth:(CGFloat)width {
    return width * 9 / 16 + 76 + 42 + 12;
}

@end

#pragma mark - Episode cell

@interface ZLEpisodeCell : UITableViewCell
@property (nonatomic, strong) UIImageView *thumbnail;
@property (nonatomic, strong) UILabel *codeLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *overviewLabel;
@property (nonatomic, strong) NSURL *thumbnailURL;
@end

@implementation ZLEpisodeCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = ZLBackgroundColor();
        self.contentView.backgroundColor = ZLBackgroundColor();
        UIView *selected = [UIView new];
        selected.backgroundColor = ZLSurfaceColor();
        self.selectedBackgroundView = selected;
        self.thumbnail = [[UIImageView alloc] initWithFrame:CGRectMake(12, 8, 112, 63)];
        self.thumbnail.contentMode = UIViewContentModeScaleAspectFill;
        self.thumbnail.clipsToBounds = YES;
        self.thumbnail.backgroundColor = ZLSurfaceColor();
        self.thumbnail.layer.cornerRadius = 3;
        [self.contentView addSubview:self.thumbnail];
        self.codeLabel = [[UILabel alloc] initWithFrame:CGRectMake(134, 6, 176, 16)];
        self.codeLabel.font = ZLBoldFont(12);
        self.codeLabel.textColor = ZLAccentColor();
        self.codeLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:self.codeLabel];
        self.nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(134, 22, 176, 18)];
        self.nameLabel.font = ZLBoldFont(14);
        self.nameLabel.textColor = ZLTextColor();
        self.nameLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:self.nameLabel];
        self.overviewLabel = [[UILabel alloc] initWithFrame:CGRectMake(134, 40, 176, 32)];
        self.overviewLabel.font = ZLFont(12);
        self.overviewLabel.textColor = ZLSecondaryTextColor();
        self.overviewLabel.backgroundColor = [UIColor clearColor];
        self.overviewLabel.numberOfLines = 2;
        [self.contentView addSubview:self.overviewLabel];
    }
    return self;
}

- (void)showEpisode:(ZLEpisode *)episode {
    NSString *code = episode.code;
    if (episode.released && [episode.released timeIntervalSinceNow] > 0) {
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.dateStyle = NSDateFormatterMediumStyle;
        code = [code stringByAppendingFormat:@"  Comes %@", [formatter stringFromDate:episode.released]];
    }
    self.codeLabel.text = code;
    self.nameLabel.text = episode.title ?: [NSString stringWithFormat:@"Episode %ld", (long)episode.episode];
    self.overviewLabel.text = episode.overview;
    self.thumbnailURL = episode.thumbnail;
    self.thumbnail.image = [[ZLImageLoader shared] cachedImageForURL:episode.thumbnail size:self.thumbnail.bounds.size];
    if (self.thumbnail.image || !episode.thumbnail) return;
    NSURL *url = episode.thumbnail;
    [[ZLImageLoader shared] loadURL:url size:self.thumbnail.bounds.size handler:^(UIImage *image) {
        if ([self.thumbnailURL isEqual:url]) self.thumbnail.image = image;
    }];
}

@end

#pragma mark - Title page

@interface ZLTitleViewController () <ZLRowCellDelegate, UIActionSheetDelegate>
@property (nonatomic, strong) ZLMeta *meta;
@property (nonatomic, strong) ZLTitleHeader *header;
@property (nonatomic) NSInteger season;
@property (nonatomic, strong) NSArray *episodes;
@property (nonatomic, strong) NSArray *more;
@property (nonatomic) BOOL loadingMeta;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation ZLTitleViewController

- (instancetype)initWithMeta:(ZLMeta *)meta {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _meta = meta;
        self.title = meta.name;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = ZLBackgroundColor();
    self.tableView.separatorColor = ZLSurfaceColor();
    [self.tableView registerClass:[ZLEpisodeCell class] forCellReuseIdentifier:@"episode"];
    [self.tableView registerClass:[ZLRowCell class] forCellReuseIdentifier:@"row"];
    [self.tableView addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(episodePressed:)]];
    self.header = [[ZLTitleHeader alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width,
                                                                   [ZLTitleHeader heightForWidth:self.view.bounds.size.width])];
    [self.header.playButton addTarget:self action:@selector(play) forControlEvents:UIControlEventTouchUpInside];
    [self.header.listButton addTarget:self action:@selector(toggleWatchlist) forControlEvents:UIControlEventTouchUpInside];
    [self.header.sourcesButton addTarget:self action:@selector(chooseSource) forControlEvents:UIControlEventTouchUpInside];
    self.tableView.tableHeaderView = self.header;
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];
    [self showMeta];
    [self loadFullMeta];
    [self loadMore];
}

- (void)loadFullMeta {
    self.loadingMeta = YES;
    [self.spinner startAnimating];
    [[ZLAddonManager shared] loadMeta:self.meta.type identifier:self.meta.identifier completion:^(ZLMeta *meta, NSError *error) {
        self.loadingMeta = NO;
        [self.spinner stopAnimating];
        if (!meta) return;
        self.meta = meta;
        [self showMeta];
    }];
}

- (void)showMeta {
    ZLMeta *meta = self.meta;
    self.title = meta.name;
    self.header.nameLabel.text = meta.name;
    self.header.factsLabel.text = meta.facts;
    self.header.genresLabel.text = [meta.genres componentsJoinedByString:@", "];
    CGSize posterSize = self.header.poster.bounds.size;
    [[ZLImageLoader shared] loadURL:meta.poster size:posterSize handler:^(UIImage *image) {
        if (image) self.header.poster.image = image;
    }];
    NSURL *backdrop = meta.background ?: meta.poster;
    [[ZLImageLoader shared] loadURL:backdrop size:CGSizeMake(self.header.backdrop.bounds.size.width, self.header.backdrop.bounds.size.width)
                            handler:^(UIImage *image) {
        if (image) self.header.backdrop.image = image;
    }];
    NSArray *seasons = meta.seasons;
    if (seasons.count && ![seasons containsObject:@(self.season)]) self.season = [seasons.firstObject integerValue];
    self.episodes = [meta episodesOfSeason:self.season];
    [self.tableView reloadData];
}

- (BOOL)isSeries {
    return self.meta.episodes.count > 1 || [self.meta.type isEqualToString:@"series"];
}

#pragma mark - More like this

// A catalog of the same addon and type, with the first genre if it can.
- (void)loadMore {
    ZLCatalog *best = nil;
    for (ZLAddon *addon in [ZLAddonManager shared].addons) {
        for (ZLCatalog *catalog in addon.catalogs) {
            if (![catalog.type isEqualToString:self.meta.type] || [catalog needsExtra]) continue;
            if (!best) best = catalog;
            if ([catalog extraNamed:@"genre"].options.count && ![best extraNamed:@"genre"].options.count) best = catalog;
        }
    }
    if (!best) return;
    NSString *genre = nil;
    for (NSString *candidate in self.meta.genres) {
        if ([[best extraNamed:@"genre"].options containsObject:candidate]) {
            genre = candidate;
            break;
        }
    }
    [[ZLAddonManager shared] loadCatalog:best extras:genre ? @{ @"genre": genre } : nil completion:^(NSArray *metas, NSError *error) {
        NSMutableArray *others = [NSMutableArray array];
        for (ZLMeta *meta in metas) {
            if (![meta.identifier isEqualToString:self.meta.identifier] && others.count < 20) [others addObject:meta];
        }
        self.more = others;
        [self.tableView reloadData];
    }];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return ZLTitleSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch ((ZLTitleSection)section) {
        case ZLTitleAbout: return 1;
        case ZLTitleEpisodes: return [self isSeries] ? (NSInteger)self.episodes.count : 0;
        case ZLTitleMore: return self.more.count ? 1 : 0;
        default: return 0;
    }
}

- (NSString *)aboutText {
    NSMutableArray *parts = [NSMutableArray array];
    if (self.meta.summary.length) [parts addObject:self.meta.summary];
    if (self.meta.directors.count) [parts addObject:[@"Director: " stringByAppendingString:[self.meta.directors componentsJoinedByString:@", "]]];
    if (self.meta.cast.count) {
        NSArray *cast = self.meta.cast.count > 8 ? [self.meta.cast subarrayWithRange:NSMakeRange(0, 8)] : self.meta.cast;
        [parts addObject:[@"Cast: " stringByAppendingString:[cast componentsJoinedByString:@", "]]];
    }
    if (!parts.count) [parts addObject:self.loadingMeta ? @"" : @"No description."];
    return [parts componentsJoinedByString:@"\n\n"];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch ((ZLTitleSection)indexPath.section) {
        case ZLTitleAbout: {
            CGSize size = [[self aboutText] sizeWithFont:ZLFont(14) constrainedToSize:CGSizeMake(tableView.bounds.size.width - 24, 2000)];
            return size.height + 16;
        }
        case ZLTitleEpisodes: return 80;
        case ZLTitleMore: return ZLRowCellHeight;
        default: return 44;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section == ZLTitleEpisodes && [self isSeries] && self.meta.seasons.count) return 44;
    return 0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section != ZLTitleEpisodes || ![self isSeries] || !self.meta.seasons.count) return nil;
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 44)];
    view.backgroundColor = ZLBackgroundColor();
    NSArray *seasons = self.meta.seasons;
    if (seasons.count <= 5) {
        NSMutableArray *titles = [NSMutableArray array];
        for (NSNumber *season in seasons) [titles addObject:season.integerValue == 0 ? @"Extras" : [NSString stringWithFormat:@"Season %@", season]];
        UISegmentedControl *control = [[UISegmentedControl alloc] initWithItems:seasons.count > 3 ? [self shortTitles:seasons] : titles];
        control.segmentedControlStyle = UISegmentedControlStyleBar;
        control.frame = CGRectMake(12, 8, view.bounds.size.width - 24, 30);
        control.selectedSegmentIndex = (NSInteger)[seasons indexOfObject:@(self.season)];
        [control addTarget:self action:@selector(seasonChanged:) forControlEvents:UIControlEventValueChanged];
        [view addSubview:control];
    } else {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.frame = CGRectMake(12, 6, 200, 32);
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        button.titleLabel.font = ZLBoldFont(17);
        [button setTitleColor:ZLAccentColor() forState:UIControlStateNormal];
        NSString *title = self.season == 0 ? @"Extras" : [NSString stringWithFormat:@"Season %ld", (long)self.season];
        [button setTitle:[title stringByAppendingString:@"  (change)"] forState:UIControlStateNormal];
        [button addTarget:self action:@selector(chooseSeason) forControlEvents:UIControlEventTouchUpInside];
        [view addSubview:button];
    }
    return view;
}

- (NSArray *)shortTitles:(NSArray *)seasons {
    NSMutableArray *titles = [NSMutableArray array];
    for (NSNumber *season in seasons) [titles addObject:season.integerValue == 0 ? @"Extras" : [NSString stringWithFormat:@"S%@", season]];
    return titles;
}

- (void)seasonChanged:(UISegmentedControl *)control {
    self.season = [self.meta.seasons[(NSUInteger)control.selectedSegmentIndex] integerValue];
    self.episodes = [self.meta episodesOfSeason:self.season];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:ZLTitleEpisodes] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)chooseSeason {
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Season" delegate:self cancelButtonTitle:nil
                                         destructiveButtonTitle:nil otherButtonTitles:nil];
    for (NSNumber *season in self.meta.seasons) {
        [sheet addButtonWithTitle:season.integerValue == 0 ? @"Extras" : [NSString stringWithFormat:@"Season %@", season]];
    }
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
    [sheet showFromTabBar:self.tabBarController.tabBar];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    if (index == sheet.cancelButtonIndex || index >= (NSInteger)self.meta.seasons.count) return;
    self.season = [self.meta.seasons[(NSUInteger)index] integerValue];
    self.episodes = [self.meta episodesOfSeason:self.season];
    [self.tableView reloadData];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == ZLTitleEpisodes) {
        ZLEpisodeCell *cell = [tableView dequeueReusableCellWithIdentifier:@"episode" forIndexPath:indexPath];
        [cell showEpisode:self.episodes[(NSUInteger)indexPath.row]];
        return cell;
    }
    if (indexPath.section == ZLTitleMore) {
        ZLRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row" forIndexPath:indexPath];
        cell.delegate = self;
        cell.title = @"More like this";
        cell.subtitle = nil;
        cell.metas = self.more;
        return cell;
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"about"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"about"];
        cell.backgroundColor = ZLBackgroundColor();
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.font = ZLFont(14);
        cell.textLabel.textColor = ZLSecondaryTextColor();
        cell.textLabel.backgroundColor = [UIColor clearColor];
    }
    cell.textLabel.text = [self aboutText];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == ZLTitleEpisodes) [self playEpisode:self.episodes[(NSUInteger)indexPath.row]];
}

// A long press on an episode shows its sources.
- (void)episodePressed:(UILongPressGestureRecognizer *)press {
    if (press.state != UIGestureRecognizerStateBegan) return;
    NSIndexPath *path = [self.tableView indexPathForRowAtPoint:[press locationInView:self.tableView]];
    if (path.section != ZLTitleEpisodes || (NSUInteger)path.row >= self.episodes.count) return;
    ZLStreamsViewController *streams = [[ZLStreamsViewController alloc] initWithMeta:self.meta episode:self.episodes[(NSUInteger)path.row]];
    [self.navigationController pushViewController:streams animated:YES];
}

- (void)rowCell:(ZLRowCell *)cell didSelectMeta:(ZLMeta *)meta atIndex:(NSUInteger)index {
    [self.navigationController pushViewController:[[ZLTitleViewController alloc] initWithMeta:meta] animated:YES];
}

- (void)rowCellDidSelectTitle:(ZLRowCell *)cell {
}

#pragma mark - Actions

- (void)play {
    // The first episode of the season that shows. The library picks the next one in 0.5.
    [self playEpisode:[self currentEpisode]];
}

- (ZLEpisode *)currentEpisode {
    if (![self isSeries] || !self.meta.episodes.count) return nil;
    return self.episodes.firstObject ?: self.meta.episodes.firstObject;
}

- (void)chooseSource {
    ZLStreamsViewController *streams = [[ZLStreamsViewController alloc] initWithMeta:self.meta episode:[self currentEpisode]];
    [self.navigationController pushViewController:streams animated:YES];
}

// Plays the best stream at once. When autoplay is off, or when no stream
// fits the phone, the stream picker shows.
- (void)playEpisode:(ZLEpisode *)episode {
    if (![ZLSettings shared].autoplay) {
        [self.navigationController pushViewController:[[ZLStreamsViewController alloc] initWithMeta:self.meta episode:episode]
                                             animated:YES];
        return;
    }
    self.header.playButton.enabled = NO;
    [self.header.playButton setTitle:@"Looking..." forState:UIControlStateNormal];
    ZLMeta *meta = self.meta;
    ZLCollectStreams(meta, episode, 8, ^(NSArray *streams) {
        self.header.playButton.enabled = YES;
        [self.header.playButton setTitle:@"Play" forState:UIControlStateNormal];
        ZLRankedStreams *ranked = ZLRankStreams(streams, NO);
        if (!ranked.streams.count) {
            [self.navigationController pushViewController:[[ZLStreamsViewController alloc] initWithMeta:meta episode:episode]
                                                 animated:YES];
            return;
        }
        [ZLPlayback playItems:[ZLStreamsViewController itemsForStreams:ranked.streams from:0 meta:meta episode:episode]
                         from:self];
    });
}

- (void)toggleWatchlist {
}

@end
