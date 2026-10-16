#import "ZLStreamsViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "ZLAddonManager.h"
#import "ZLPlayback.h"
#import "ZLSettings.h"
#import "ZLStreamRank.h"
#import "ZLTheme.h"
#import "ZLWatch.h"

void ZLCollectStreams(ZLMeta *meta, ZLEpisode *episode, NSTimeInterval limit, void (^completion)(NSArray *streams)) {
    NSMutableArray *streams = [NSMutableArray array];
    __block BOOL finished = NO;
    void (^finish)(void) = ^{
        if (finished) return;
        finished = YES;
        completion(streams);
    };
    [[ZLAddonManager shared] loadStreams:meta.type identifier:episode.identifier ?: meta.identifier
        each:^(ZLAddon *addon, NSArray *found, NSError *error) {
            if (!finished) [streams addObjectsFromArray:found];
        }
        done:finish];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(limit * NSEC_PER_SEC)), dispatch_get_main_queue(), finish);
}

#pragma mark - Cell

@interface ZLStreamCell : UITableViewCell
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *textBody;
@property (nonatomic, strong) UIView *badgeRow;
@end

@implementation ZLStreamCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = ZLBackgroundColor();
        UIView *selected = [UIView new];
        selected.backgroundColor = ZLSurfaceColor();
        self.selectedBackgroundView = selected;
        self.nameLabel = [UILabel new];
        self.nameLabel.font = ZLBoldFont(14);
        self.nameLabel.textColor = ZLTextColor();
        self.nameLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:self.nameLabel];
        self.badgeRow = [UIView new];
        [self.contentView addSubview:self.badgeRow];
        self.textBody = [UILabel new];
        self.textBody.font = ZLFont(12);
        self.textBody.textColor = ZLSecondaryTextColor();
        self.textBody.backgroundColor = [UIColor clearColor];
        self.textBody.numberOfLines = 0;
        [self.contentView addSubview:self.textBody];
    }
    return self;
}

+ (CGFloat)textHeight:(NSString *)text width:(CGFloat)width {
    return [text ?: @"" sizeWithFont:ZLFont(12) constrainedToSize:CGSizeMake(width - 24, 400)].height;
}

- (void)showStream:(ZLStream *)stream info:(ZLStreamInfo *)info width:(CGFloat)width {
    self.nameLabel.frame = CGRectMake(12, 8, width - 24, 18);
    NSString *name = [stream.name stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    self.nameLabel.text = name.length ? [NSString stringWithFormat:@"%@  (%@)", name, stream.addonName] : stream.addonName;
    for (UIView *view in self.badgeRow.subviews) [view removeFromSuperview];
    CGFloat x = 0;
    for (NSString *badge in [info badges]) {
        UILabel *label = [UILabel new];
        label.text = badge;
        label.font = ZLBoldFont(10);
        label.textAlignment = NSTextAlignmentCenter;
        BOOL warning = [badge isEqualToString:@"Too heavy"];
        BOOL soft = [badge isEqualToString:@"Software"];
        label.textColor = warning || soft ? [UIColor blackColor] : ZLTextColor();
        label.backgroundColor = warning ? [UIColor colorWithRed:0.9 green:0.3 blue:0.25 alpha:1] : soft ? ZLAccentColor() : [UIColor colorWithWhite:0.22 alpha:1];
        label.layer.cornerRadius = 3;
        CGFloat labelWidth = [badge sizeWithFont:label.font].width + 10;
        if (x + labelWidth > width - 24) break;
        label.frame = CGRectMake(x, 0, labelWidth, 16);
        x += labelWidth + 4;
        [self.badgeRow addSubview:label];
    }
    self.badgeRow.frame = CGRectMake(12, 30, width - 24, 16);
    self.textBody.text = stream.title ?: stream.filename;
    self.textBody.frame = CGRectMake(12, 50, width - 24, [ZLStreamCell textHeight:self.textBody.text width:width]);
}

@end

#pragma mark - Streams

@interface ZLStreamsViewController ()
@property (nonatomic, strong) ZLMeta *meta;
@property (nonatomic, strong) ZLEpisode *episode;
@property (nonatomic, strong) NSMutableArray *found;
@property (nonatomic, strong) ZLRankedStreams *ranked;
@property (nonatomic) BOOL done;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation ZLStreamsViewController

- (instancetype)initWithMeta:(ZLMeta *)meta episode:(ZLEpisode *)episode {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _meta = meta;
        _episode = episode;
        _found = [NSMutableArray array];
        self.title = episode ? [episode code] : @"Sources";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = ZLBackgroundColor();
    self.tableView.separatorColor = ZLSurfaceColor();
    [self.tableView registerClass:[ZLStreamCell class] forCellReuseIdentifier:@"stream"];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];
    [self.spinner startAnimating];
    [self rank];
    [[ZLAddonManager shared] loadStreams:self.meta.type identifier:self.episode.identifier ?: self.meta.identifier
        each:^(ZLAddon *addon, NSArray *streams, NSError *error) {
            [self.found addObjectsFromArray:streams];
            [self rank];
        }
        done:^{
            self.done = YES;
            [self.spinner stopAnimating];
            [self rank];
        }];
}

- (void)rank {
    self.ranked = ZLRankStreams(self.found, [ZLSettings shared].showHeavyStreams);
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.ranked.streams.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    ZLStream *stream = self.ranked.streams[(NSUInteger)indexPath.row];
    return 58 + [ZLStreamCell textHeight:stream.title ?: stream.filename width:tableView.bounds.size.width];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ZLStreamCell *cell = [tableView dequeueReusableCellWithIdentifier:@"stream" forIndexPath:indexPath];
    NSUInteger row = (NSUInteger)indexPath.row;
    [cell showStream:self.ranked.streams[row] info:self.ranked.infos[row] width:tableView.bounds.size.width];
    return cell;
}

- (NSString *)footerText {
    NSMutableArray *parts = [NSMutableArray array];
    if (!self.done) [parts addObject:@"The addons look for streams."];
    else if (!self.found.count) [parts addObject:@"No addon has a stream for this title."];
    if (self.done && !self.ranked.streams.count && self.ranked.torrents && !self.ranked.heavy) {
        [parts addObject:@"This addon gave only torrent streams. Add a debrid key in its settings."];
    } else if (self.ranked.torrents) {
        NSUInteger count = self.ranked.torrents;
        [parts addObject:count == 1 ? @"1 torrent stream does not show."
                                    : [NSString stringWithFormat:@"%lu torrent streams do not show.", (unsigned long)count]];
    }
    if (self.ranked.heavy && ![ZLSettings shared].showHeavyStreams) {
        NSUInteger count = self.ranked.heavy;
        [parts addObject:count == 1 ? @"1 stream is too heavy for the phone. Settings, Playback, Show heavy streams, shows it."
                                    : [NSString stringWithFormat:@"%lu streams are too heavy for the phone. Settings, Playback, "
                                                                 @"Show heavy streams, shows them.", (unsigned long)count]];
    }
    return [parts componentsJoinedByString:@"\n\n"];
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    NSString *text = [self footerText];
    if (!text.length) return 0;
    return [text sizeWithFont:ZLFont(13) constrainedToSize:CGSizeMake(tableView.bounds.size.width - 24, 400)].height + 24;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    NSString *text = [self footerText];
    if (!text.length) return nil;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(12, 12, tableView.bounds.size.width - 24, 0)];
    label.text = text;
    label.font = ZLFont(13);
    label.textColor = ZLSecondaryTextColor();
    label.backgroundColor = [UIColor clearColor];
    label.numberOfLines = 0;
    [label sizeToFit];
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, label.frame.size.height + 24)];
    [view addSubview:label];
    return view;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray *items = [ZLWatch itemsForStreams:self.ranked.streams from:(NSUInteger)indexPath.row meta:self.meta episode:self.episode];
    [ZLPlayback playItems:items from:self];
}

@end
