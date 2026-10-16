#import "ZLSettingsViewController.h"
#import "ZLAddonManager.h"
#import "ZLLinkViewController.h"
#import "ZLLog.h"
#import "ZLSources.h"
#import "ZLTheme.h"
#import "ZLTrust.h"

#pragma mark - Sources

// The source list as text, as in ZettaStream: paste the list, and press Save.
@interface ZLSourcesViewController : UIViewController
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation ZLSourcesViewController

- (void)loadView {
    UIView *view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].applicationFrame];
    view.backgroundColor = ZLBackgroundColor();
    CGFloat width = view.bounds.size.width;
    UILabel *intro = [[UILabel alloc] initWithFrame:CGRectMake(12, 8, width - 24, 54)];
    intro.text = @"One link on each line: a Stremio addon (manifest.json), an M3U playlist, or a media link. "
                 @"The new list replaces the old list.";
    intro.numberOfLines = 0;
    intro.font = ZLFont(13);
    intro.textColor = ZLSecondaryTextColor();
    intro.backgroundColor = [UIColor clearColor];
    [view addSubview:intro];
    self.textView = [[UITextView alloc] initWithFrame:CGRectMake(12, 66, width - 24, 170)];
    self.textView.font = [UIFont fontWithName:@"Courier" size:12];
    self.textView.backgroundColor = ZLSurfaceColor();
    self.textView.textColor = ZLTextColor();
    self.textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.textView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textView.keyboardType = UIKeyboardTypeURL;
    self.textView.text = [[ZLSourceList shared] text];
    [view addSubview:self.textView];
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 242, width - 24, 120)];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = ZLFont(12);
    self.statusLabel.textColor = ZLSecondaryTextColor();
    self.statusLabel.backgroundColor = [UIColor clearColor];
    [view addSubview:self.statusLabel];
    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Sources";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Save" style:UIBarButtonItemStyleDone
                                                                             target:self action:@selector(save)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Paste" style:UIBarButtonItemStyleBordered
                                                                            target:self action:@selector(paste)];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateStatus)
                                                 name:ZLAddonsDidChangeNotification object:nil];
    [self updateStatus];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)paste {
    NSString *text = [UIPasteboard generalPasteboard].string;
    if (!text.length) return;
    self.textView.text = self.textView.text.length ? [self.textView.text stringByAppendingFormat:@"\n%@", text] : text;
}

- (void)save {
    [self.textView resignFirstResponder];
    NSUInteger count = [[ZLSourceList shared] setText:self.textView.text];
    self.textView.text = [[ZLSourceList shared] text];
    self.statusLabel.text = [NSString stringWithFormat:@"Saved %lu sources. The addons load.", (unsigned long)count];
}

- (void)updateStatus {
    NSMutableArray *lines = [NSMutableArray array];
    for (ZLAddon *addon in [ZLAddonManager shared].addons) {
        [lines addObject:[NSString stringWithFormat:@"%@ %@: %lu catalogs", addon.name, addon.version ?: @"",
                                                    (unsigned long)addon.catalogs.count]];
    }
    [[ZLAddonManager shared].failures enumerateKeysAndObjectsUsingBlock:^(NSString *url, NSString *text, BOOL *stop) {
        [lines addObject:[NSString stringWithFormat:@"Failed: %@ (%@)", url, text]];
    }];
    NSUInteger playlists = [[ZLSourceList shared] sourcesOfKind:ZLSourcePlaylist].count;
    if (playlists) [lines addObject:[NSString stringWithFormat:@"%lu playlists for Live TV", (unsigned long)playlists]];
    self.statusLabel.text = [lines componentsJoinedByString:@"\n"];
}

@end

#pragma mark - Trusted hosts

@interface ZLHostsViewController : UITableViewController
@end

@implementation ZLHostsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Trusted hosts";
    self.tableView.backgroundColor = ZLBackgroundColor();
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[[ZLTrust shared] hosts].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"The app trusts these hosts although their certificates failed the check. Remove a host to ask again.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"host"] ?:
        [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"host"];
    cell.backgroundColor = ZLSurfaceColor();
    cell.textLabel.textColor = ZLTextColor();
    cell.textLabel.font = ZLFont(15);
    cell.textLabel.text = [[ZLTrust shared] hosts][(NSUInteger)indexPath.row];
    return cell;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style
    forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (style != UITableViewCellEditingStyleDelete) return;
    [[ZLTrust shared] forgetHost:[[ZLTrust shared] hosts][(NSUInteger)indexPath.row]];
    [tableView deleteRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationAutomatic];
}

@end

#pragma mark - Diagnostics

@interface ZLDiagnosticsViewController : UIViewController
@end

@implementation ZLDiagnosticsViewController

- (void)loadView {
    UITextView *text = [[UITextView alloc] initWithFrame:[UIScreen mainScreen].applicationFrame];
    text.editable = NO;
    text.backgroundColor = ZLBackgroundColor();
    text.textColor = ZLSecondaryTextColor();
    text.font = [UIFont fontWithName:@"Courier" size:10];
    NSString *log = ZLLogText();
    // The newest lines first.
    NSArray *lines = [[log componentsSeparatedByString:@"\n"] reverseObjectEnumerator].allObjects;
    text.text = [lines componentsJoinedByString:@"\n"];
    self.view = text;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Diagnostics";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Copy" style:UIBarButtonItemStyleBordered
                                                                             target:self action:@selector(copyLog)];
}

- (void)copyLog {
    [UIPasteboard generalPasteboard].string = ZLLogText();
}

@end

#pragma mark - Settings

typedef NS_ENUM(NSInteger, ZLSettingsRow) {
    ZLSettingsSources,
    ZLSettingsLink,
    ZLSettingsHosts,
    ZLSettingsDiagnostics,
    ZLSettingsVersion,
    ZLSettingsRowCount,
};

@implementation ZLSettingsViewController

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        self.title = @"Settings";
        self.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Settings" image:[UIImage imageNamed:@"Tab-settings"] tag:4];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundView = nil;
    self.tableView.backgroundColor = ZLBackgroundColor();
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return ZLSettingsRowCount;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.backgroundColor = ZLSurfaceColor();
    cell.textLabel.textColor = ZLTextColor();
    cell.textLabel.font = ZLBoldFont(16);
    cell.detailTextLabel.textColor = ZLSecondaryTextColor();
    cell.detailTextLabel.font = ZLFont(14);
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    switch ((ZLSettingsRow)indexPath.row) {
        case ZLSettingsSources:
            cell.textLabel.text = @"Sources";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)[[ZLSourceList shared] sources].count];
            break;
        case ZLSettingsLink:
            cell.textLabel.text = @"Play a link";
            break;
        case ZLSettingsHosts:
            cell.textLabel.text = @"Trusted hosts";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)[[ZLTrust shared] hosts].count];
            break;
        case ZLSettingsDiagnostics:
            cell.textLabel.text = @"Diagnostics";
            break;
        case ZLSettingsVersion:
            cell.textLabel.text = @"Version";
            cell.detailTextLabel.text = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        default:
            break;
    }
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"ZettaLite is free software under the MIT licence. It uses FFmpeg (LGPL 2.1), dav1d (BSD), mbedTLS "
           @"(Apache 2.0), the Mozilla root certificates (MPL 2.0), and the Karla font (OFL).";
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    UIViewController *next = nil;
    switch ((ZLSettingsRow)indexPath.row) {
        case ZLSettingsSources: next = [ZLSourcesViewController new]; break;
        case ZLSettingsLink: next = [ZLLinkViewController new]; break;
        case ZLSettingsHosts: next = [[ZLHostsViewController alloc] initWithStyle:UITableViewStyleGrouped]; break;
        case ZLSettingsDiagnostics: next = [ZLDiagnosticsViewController new]; break;
        default: break;
    }
    if (next) [self.navigationController pushViewController:next animated:YES];
}

- (void)showSources {
    [self.navigationController popToRootViewControllerAnimated:NO];
    [self.navigationController pushViewController:[ZLSourcesViewController new] animated:NO];
}

@end
