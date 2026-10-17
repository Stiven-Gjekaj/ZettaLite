#import "ZLSettingsViewController.h"
#import "ZLAddonManager.h"
#import "ZLLibrary.h"
#import "ZLLinkViewController.h"
#import "ZLLog.h"
#import "ZLSettings.h"
#import "ZLChannels.h"
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

#pragma mark - Playback

// The switches of the playback, the audio language, and the subtitles.
@interface ZLPlaybackSettingsViewController : UITableViewController <UIActionSheetDelegate>
@end

// The tags of the sheets.
enum { ZLSheetAudio = 1, ZLSheetSubtitleLanguage, ZLSheetSubtitleSize };

@implementation ZLPlaybackSettingsViewController

- (NSArray *)languages {
    return @[ @[ @"English", @"eng" ], @[ @"German", @"ger" ], @[ @"French", @"fre" ], @[ @"Spanish", @"spa" ],
              @[ @"Italian", @"ita" ], @[ @"Albanian", @"alb" ], @[ @"Portuguese", @"por" ], @[ @"Japanese", @"jpn" ],
              @[ @"Russian", @"rus" ], @[ @"Turkish", @"tur" ] ];
}

- (NSArray *)audioLanguages {
    return [@[ @[ @"The language of the phone", [NSNull null] ] ] arrayByAddingObjectsFromArray:[self languages]];
}

- (NSArray *)subtitleLanguages {
    return [@[ @[ @"Off", [NSNull null] ] ] arrayByAddingObjectsFromArray:[self languages]];
}

- (NSArray *)subtitleSizes {
    return @[ @[ @"Small", @15 ], @[ @"Medium", @18 ], @[ @"Large", @22 ], @[ @"Very large", @26 ] ];
}

- (NSArray *)choicesForSheet:(NSInteger)tag {
    if (tag == ZLSheetAudio) return [self audioLanguages];
    if (tag == ZLSheetSubtitleLanguage) return [self subtitleLanguages];
    return [self subtitleSizes];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Playback";
    self.tableView.backgroundView = nil;
    self.tableView.backgroundColor = ZLBackgroundColor();
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 3 : section == 1 ? 1 : 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"Autoplay: Play starts the best stream at once, and the next one when a stream fails. Sources shows all "
               @"streams. A heavy stream needs more than the A5 chip can decode.";
    }
    if (section == 1) return @"The player picks this audio track first, when a file has more than one.";
    return @"The player shows subtitles in this language at the start. It looks in the file first, then in the subtitle "
           @"addons. Subs in the player changes them.";
}

// The name of a value in a list of choices.
- (NSString *)nameOf:(id)value in:(NSArray *)choices {
    for (NSArray *pair in choices) {
        if ([pair[1] isEqual:value ?: [NSNull null]]) return pair[0];
    }
    return [value description];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.backgroundColor = ZLSurfaceColor();
    cell.textLabel.textColor = ZLTextColor();
    cell.textLabel.font = ZLBoldFont(15);
    cell.detailTextLabel.textColor = ZLSecondaryTextColor();
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    ZLSettings *settings = [ZLSettings shared];
    if (indexPath.section > 0) {
        if (indexPath.section == 1) {
            cell.textLabel.text = @"Audio language";
            cell.detailTextLabel.text = [self nameOf:settings.audioLanguage in:[self audioLanguages]];
        } else if (indexPath.row == 0) {
            cell.textLabel.text = @"Subtitle language";
            cell.detailTextLabel.text = [self nameOf:settings.subtitleLanguage in:[self subtitleLanguages]];
        } else {
            cell.textLabel.text = @"Subtitle size";
            cell.detailTextLabel.text = [self nameOf:@((NSInteger)settings.subtitleSize) in:[self subtitleSizes]];
        }
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        return cell;
    }
    UISwitch *toggle = [UISwitch new];
    toggle.tag = indexPath.row;
    [toggle addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];
    NSArray *titles = @[ @"Autoplay", @"Show heavy streams", @"Play the next episode" ];
    NSArray *values = @[ @(settings.autoplay), @(settings.showHeavyStreams), @(settings.playNextEpisode) ];
    cell.textLabel.text = titles[(NSUInteger)indexPath.row];
    toggle.on = [values[(NSUInteger)indexPath.row] boolValue];
    cell.accessoryView = toggle;
    return cell;
}

- (void)toggled:(UISwitch *)toggle {
    ZLSettings *settings = [ZLSettings shared];
    if (toggle.tag == 0) settings.autoplay = toggle.on;
    if (toggle.tag == 1) settings.showHeavyStreams = toggle.on;
    if (toggle.tag == 2) settings.playNextEpisode = toggle.on;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) return;
    NSInteger tag = indexPath.section == 1 ? ZLSheetAudio : indexPath.row == 0 ? ZLSheetSubtitleLanguage : ZLSheetSubtitleSize;
    NSString *title = [tableView cellForRowAtIndexPath:indexPath].textLabel.text;
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:title delegate:self cancelButtonTitle:nil
                                         destructiveButtonTitle:nil otherButtonTitles:nil];
    sheet.tag = tag;
    for (NSArray *pair in [self choicesForSheet:tag]) [sheet addButtonWithTitle:pair[0]];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
    [sheet showFromTabBar:self.tabBarController.tabBar];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    NSArray *choices = [self choicesForSheet:sheet.tag];
    if (index == sheet.cancelButtonIndex || index < 0 || index >= (NSInteger)choices.count) return;
    id value = choices[(NSUInteger)index][1];
    ZLSettings *settings = [ZLSettings shared];
    if (sheet.tag == ZLSheetAudio) settings.audioLanguage = value == [NSNull null] ? nil : value;
    if (sheet.tag == ZLSheetSubtitleLanguage) settings.subtitleLanguage = value == [NSNull null] ? nil : value;
    if (sheet.tag == ZLSheetSubtitleSize) settings.subtitleSize = [value doubleValue];
    [self.tableView reloadData];
}

@end

#pragma mark - Backup

// A backup holds the library, the sources, the trusted hosts, and the settings.
// It goes to the clipboard and to Documents, where iTunes File Sharing shows it.
@interface ZLBackupViewController : UITableViewController <UIAlertViewDelegate>
@end

@implementation ZLBackupViewController

+ (NSString *)backupPath {
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [documents stringByAppendingPathComponent:@"ZettaLite-backup.json"];
}

+ (NSDictionary *)backup {
    ZLSettings *settings = [ZLSettings shared];
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    values[@"autoplay"] = @(settings.autoplay);
    values[@"showHeavyStreams"] = @(settings.showHeavyStreams);
    values[@"playNextEpisode"] = @(settings.playNextEpisode);
    values[@"subtitleSize"] = @(settings.subtitleSize);
    if (settings.audioLanguage) values[@"audioLanguage"] = settings.audioLanguage;
    if (settings.subtitleLanguage) values[@"subtitleLanguage"] = settings.subtitleLanguage;
    return @{ @"app": @"ZettaLite", @"version": @1, @"library": [[ZLLibrary shared] backup],
              @"sources": [[ZLSourceList shared] text], @"trustedHosts": [[ZLTrust shared] hosts], @"favourites": [[ZLChannelList shared] favouriteKeys],
              @"settings": values };
}

+ (BOOL)restore:(NSDictionary *)backup {
    if (![backup isKindOfClass:[NSDictionary class]] || ![backup[@"app"] isEqual:@"ZettaLite"]) return NO;
    if (![[ZLLibrary shared] restore:backup[@"library"]]) return NO;
    if ([backup[@"sources"] isKindOfClass:[NSString class]]) [[ZLSourceList shared] setText:backup[@"sources"]];
    if ([backup[@"favourites"] isKindOfClass:[NSArray class]]) [[ZLChannelList shared] setFavouriteKeys:backup[@"favourites"]];
    for (id host in backup[@"trustedHosts"]) {
        if ([host isKindOfClass:[NSString class]]) [[ZLTrust shared] trustHost:host];
    }
    NSDictionary *values = backup[@"settings"];
    if ([values isKindOfClass:[NSDictionary class]]) {
        ZLSettings *settings = [ZLSettings shared];
        if (values[@"autoplay"]) settings.autoplay = [values[@"autoplay"] boolValue];
        if (values[@"showHeavyStreams"]) settings.showHeavyStreams = [values[@"showHeavyStreams"] boolValue];
        if (values[@"playNextEpisode"]) settings.playNextEpisode = [values[@"playNextEpisode"] boolValue];
        if (values[@"subtitleSize"]) settings.subtitleSize = [values[@"subtitleSize"] doubleValue];
        settings.audioLanguage = [values[@"audioLanguage"] isKindOfClass:[NSString class]] ? values[@"audioLanguage"] : nil;
        settings.subtitleLanguage = [values[@"subtitleLanguage"] isKindOfClass:[NSString class]] ? values[@"subtitleLanguage"] : nil;
    }
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Backup";
    self.tableView.backgroundView = nil;
    self.tableView.backgroundColor = ZLBackgroundColor();
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"A backup holds the library, the sources, the trusted hosts, and the settings. It goes to the clipboard, "
           @"and to ZettaLite-backup.json in the files of the app in iTunes. A restore replaces the library and the sources.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = ZLSurfaceColor();
    cell.textLabel.textColor = indexPath.row == 0 ? ZLAccentColor() : ZLTextColor();
    cell.textLabel.font = ZLBoldFont(15);
    NSArray *titles = @[ @"Make a backup", @"Restore from the clipboard", @"Restore from the backup file" ];
    cell.textLabel.text = titles[(NSUInteger)indexPath.row];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row == 0) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:[ZLBackupViewController backup] options:NSJSONWritingPrettyPrinted error:NULL];
        [data writeToFile:[ZLBackupViewController backupPath] atomically:YES];
        [UIPasteboard generalPasteboard].string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        [[[UIAlertView alloc] initWithTitle:@"Backup made" message:@"The backup is in the clipboard and in the files of the app."
                                   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        return;
    }
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Restore?" message:@"The backup replaces the library and the sources."
                                                   delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Restore", nil];
    alert.tag = indexPath.row;
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == alertView.cancelButtonIndex) return;
    NSData *data = alertView.tag == 1 ? [[UIPasteboard generalPasteboard].string dataUsingEncoding:NSUTF8StringEncoding]
                                      : [NSData dataWithContentsOfFile:[ZLBackupViewController backupPath]];
    id backup = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    BOOL ok = [ZLBackupViewController restore:backup];
    [[[UIAlertView alloc] initWithTitle:ok ? @"Restored" : @"No backup"
                                message:ok ? @"The library, the sources, and the settings are back." : @"The app found no ZettaLite backup there."
                               delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
}

@end

#pragma mark - Settings

typedef NS_ENUM(NSInteger, ZLSettingsRow) {
    ZLSettingsSources,
    ZLSettingsPlayback,
    ZLSettingsLink,
    ZLSettingsHosts,
    ZLSettingsBackup,
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
        case ZLSettingsPlayback:
            cell.textLabel.text = @"Playback";
            break;
        case ZLSettingsLink:
            cell.textLabel.text = @"Play a link";
            break;
        case ZLSettingsHosts:
            cell.textLabel.text = @"Trusted hosts";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)[[ZLTrust shared] hosts].count];
            break;
        case ZLSettingsBackup:
            cell.textLabel.text = @"Backup and restore";
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
        case ZLSettingsPlayback: next = [[ZLPlaybackSettingsViewController alloc] initWithStyle:UITableViewStyleGrouped]; break;
        case ZLSettingsLink: next = [ZLLinkViewController new]; break;
        case ZLSettingsHosts: next = [[ZLHostsViewController alloc] initWithStyle:UITableViewStyleGrouped]; break;
        case ZLSettingsBackup: next = [[ZLBackupViewController alloc] initWithStyle:UITableViewStyleGrouped]; break;
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
