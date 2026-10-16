#import "ZLLinkViewController.h"
#import "ZLLink.h"
#import "ZLPlayback.h"
#import "ZLTheme.h"

@interface ZLLinkViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UIButton *playButton;
@end

@implementation ZLLinkViewController

- (instancetype)init {
    if ((self = [super init])) {
        self.title = @"Play a link";
        self.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Link" image:[UIImage imageNamed:@"Tab-link"] tag:0];
    }
    return self;
}

- (void)loadView {
    UIView *view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].applicationFrame];
    view.backgroundColor = ZLBackgroundColor();
    CGFloat width = view.bounds.size.width;

    UILabel *intro = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, width - 40, 60)];
    intro.text = @"Paste the link of a video, a song, or a stream. MKV, MP4, WebM, TS, HLS, and DASH play.";
    intro.numberOfLines = 0;
    intro.font = ZLFont(15);
    intro.textColor = ZLSecondaryTextColor();
    intro.backgroundColor = [UIColor clearColor];
    [view addSubview:intro];

    self.field = [[UITextField alloc] initWithFrame:CGRectMake(20, 90, width - 40, 36)];
    self.field.borderStyle = UITextBorderStyleRoundedRect;
    self.field.placeholder = @"https://";
    self.field.keyboardType = UIKeyboardTypeURL;
    self.field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.field.autocorrectionType = UITextAutocorrectionTypeNo;
    self.field.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.field.returnKeyType = UIReturnKeyGo;
    self.field.font = ZLFont(16);
    self.field.delegate = self;
    [view addSubview:self.field];

    self.playButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.playButton.frame = CGRectMake(20, 140, width - 40, 44);
    [self.playButton setTitle:@"Play" forState:UIControlStateNormal];
    [self.playButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.playButton.titleLabel.font = ZLBoldFont(18);
    self.playButton.backgroundColor = ZLAccentColor();
    self.playButton.layer.cornerRadius = 8;
    [self.playButton addTarget:self action:@selector(play) forControlEvents:UIControlEventTouchUpInside];
    [view addSubview:self.playButton];

    UIButton *paste = [UIButton buttonWithType:UIButtonTypeCustom];
    paste.frame = CGRectMake(20, 196, width - 40, 36);
    [paste setTitle:@"Paste from the clipboard" forState:UIControlStateNormal];
    [paste setTitleColor:ZLAccentColor() forState:UIControlStateNormal];
    paste.titleLabel.font = ZLFont(15);
    [paste addTarget:self action:@selector(paste) forControlEvents:UIControlEventTouchUpInside];
    [view addSubview:paste];
    self.view = view;
}

- (void)paste {
    NSString *text = [UIPasteboard generalPasteboard].string;
    if (text.length) self.field.text = text;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self play];
    return NO;
}

- (void)play {
    NSURL *url = ZLMediaURLFromText(self.field.text);
    if (!url) {
        [[[UIAlertView alloc] initWithTitle:@"This is not a link" message:@"A link starts with http:// or https://."
                                   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        return;
    }
    [self.field resignFirstResponder];
    [self playURL:url title:nil startTime:0];
}

- (void)playURL:(NSURL *)url title:(NSString *)title startTime:(double)startTime {
    self.field.text = url.absoluteString;
    ZLPlayItem *item = [ZLPlayItem itemWithURL:url title:title ?: url.lastPathComponent];
    item.startTime = startTime;
    [ZLPlayback play:item from:self];
}

@end
