#import "ZLStreamsViewController.h"
#import "ZLAddonManager.h"
#import "ZLPlayback.h"
#import "ZLTheme.h"

@interface ZLStreamsViewController ()
@property (nonatomic, strong) ZLMeta *meta;
@property (nonatomic, strong) ZLEpisode *episode;
@property (nonatomic, strong) NSMutableArray *streams;
@property (nonatomic) NSUInteger torrents;
@property (nonatomic) BOOL done;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation ZLStreamsViewController

- (instancetype)initWithMeta:(ZLMeta *)meta episode:(ZLEpisode *)episode {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _meta = meta;
        _episode = episode;
        _streams = [NSMutableArray array];
        self.title = episode ? episode.code : @"Streams";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = ZLBackgroundColor();
    self.tableView.separatorColor = ZLSurfaceColor();
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];
    [self.spinner startAnimating];
    NSString *identifier = self.episode.identifier ?: self.meta.identifier;
    [[ZLAddonManager shared] loadStreams:self.meta.type identifier:identifier
        each:^(ZLAddon *addon, NSArray *streams, NSError *error) {
            for (ZLStream *stream in streams) {
                if (stream.isTorrent) self.torrents++;
                else if (stream.URL) [self.streams addObject:stream];
            }
            [self.tableView reloadData];
        }
        done:^{
            self.done = YES;
            [self.spinner stopAnimating];
            [self.tableView reloadData];
        }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)MAX(self.streams.count, 1u);
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.streams.count) return 120;
    ZLStream *stream = self.streams[(NSUInteger)indexPath.row];
    CGSize size = [stream.title ?: @"" sizeWithFont:ZLFont(12) constrainedToSize:CGSizeMake(tableView.bounds.size.width - 24, 200)];
    return 32 + size.height + 8;
}

- (NSString *)emptyText {
    if (!self.done) return @"The addons look for streams.";
    if (self.torrents) {
        return @"This addon gave only torrent streams. Add a debrid key in its settings, so that it gives HTTP links.";
    }
    return @"No addon has a stream for this title.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"stream"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"stream"];
        cell.backgroundColor = ZLBackgroundColor();
        cell.textLabel.font = ZLBoldFont(14);
        cell.textLabel.textColor = ZLTextColor();
        cell.textLabel.backgroundColor = [UIColor clearColor];
        cell.detailTextLabel.font = ZLFont(12);
        cell.detailTextLabel.textColor = ZLSecondaryTextColor();
        cell.detailTextLabel.backgroundColor = [UIColor clearColor];
        cell.detailTextLabel.numberOfLines = 0;
        UIView *selected = [UIView new];
        selected.backgroundColor = ZLSurfaceColor();
        cell.selectedBackgroundView = selected;
    }
    if (!self.streams.count) {
        cell.textLabel.text = nil;
        cell.detailTextLabel.text = [self emptyText];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    ZLStream *stream = self.streams[(NSUInteger)indexPath.row];
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    cell.textLabel.text = [[stream.name ?: stream.addonName stringByReplacingOccurrencesOfString:@"\n" withString:@" "]
        stringByAppendingFormat:@"  (%@)", stream.addonName];
    cell.detailTextLabel.text = stream.title;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.streams.count) return;
    ZLStream *stream = self.streams[(NSUInteger)indexPath.row];
    NSString *title = self.episode ? [NSString stringWithFormat:@"%@ %@", self.meta.name, self.episode.code] : self.meta.name;
    ZLPlayItem *item = [ZLPlayItem itemWithURL:stream.URL title:title];
    item.headers = stream.headers;
    [ZLPlayback play:item from:self];
}

@end
