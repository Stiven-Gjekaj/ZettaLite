#import "ZLSoftwarePlayerViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "ZLLog.h"
#import "ZLTheme.h"
#import "ZLVideoView.h"

static NSString *ZLTimeText(double seconds) {
    if (!(seconds >= 0)) seconds = 0;
    long total = (long)seconds;
    if (total >= 3600) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", total / 3600, total / 60 % 60, total % 60];
    return [NSString stringWithFormat:@"%ld:%02ld", total / 60, total % 60];
}

@interface ZLSoftwarePlayerViewController () <ZLPlayerEngineDelegate, UIActionSheetDelegate>
@property (nonatomic, strong) ZLPlayerEngine *engine;
@property (nonatomic, strong) ZLVideoView *videoView;
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *elapsedLabel;
@property (nonatomic, strong) UILabel *remainingLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic) BOOL dragging;
@property (nonatomic) BOOL controlsShown;
@property (nonatomic, strong) NSTimer *hideTimer;
@property (nonatomic, strong) NSArray *audioChoices;
@end

@implementation ZLSoftwarePlayerViewController

- (instancetype)initWithEngine:(ZLPlayerEngine *)engine {
    if ((self = [super init])) {
        _engine = engine;
        _engine.delegate = self;
        self.wantsFullScreenLayout = YES;
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

- (BOOL)shouldAutorotate {
    return YES;
}

#pragma mark - Views

- (UIButton *)barButton:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [button setTitleColor:ZLAccentColor() forState:UIControlStateHighlighted];
    button.titleLabel.font = ZLBoldFont(15);
    button.layer.cornerRadius = 5;
    button.layer.borderWidth = 1;
    button.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
    button.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.9];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIView *)barView {
    UIView *bar = [UIView new];
    bar.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.75];
    return bar;
}

- (UILabel *)timeLabel:(NSTextAlignment)alignment {
    UILabel *label = [UILabel new];
    label.font = ZLFont(13);
    label.textColor = [UIColor whiteColor];
    label.backgroundColor = [UIColor clearColor];
    label.textAlignment = alignment;
    label.text = @"0:00";
    return label;
}

- (void)loadView {
    UIView *view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    view.backgroundColor = [UIColor blackColor];
    self.videoView = [[ZLVideoView alloc] initWithFrame:view.bounds];
    self.videoView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [view addSubview:self.videoView];

    self.topBar = [self barView];
    [self.topBar addSubview:[self barButton:@"Done" action:@selector(done)]];
    self.titleLabel = [UILabel new];
    self.titleLabel.font = ZLBoldFont(15);
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.backgroundColor = [UIColor clearColor];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.text = self.titleText;
    [self.topBar addSubview:self.titleLabel];
    [self.topBar addSubview:[self barButton:@"Fit" action:@selector(toggleGravity:)]];
    [view addSubview:self.topBar];

    self.bottomBar = [self barView];
    self.playButton = [self barButton:@"Pause" action:@selector(togglePause)];
    [self.bottomBar addSubview:self.playButton];
    self.elapsedLabel = [self timeLabel:NSTextAlignmentRight];
    self.remainingLabel = [self timeLabel:NSTextAlignmentLeft];
    [self.bottomBar addSubview:self.elapsedLabel];
    [self.bottomBar addSubview:self.remainingLabel];
    self.slider = [UISlider new];
    self.slider.minimumTrackTintColor = ZLAccentColor();
    [self.slider addTarget:self action:@selector(sliderStarted) forControlEvents:UIControlEventTouchDown];
    [self.slider addTarget:self action:@selector(sliderMoved) forControlEvents:UIControlEventValueChanged];
    [self.slider addTarget:self action:@selector(sliderEnded)
          forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    self.slider.enabled = self.engine.duration > 0;
    [self.bottomBar addSubview:self.slider];
    [self.bottomBar addSubview:[self barButton:@"Audio" action:@selector(chooseAudio)]];
    [view addSubview:self.bottomBar];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    self.spinner.hidesWhenStopped = YES;
    [self.spinner startAnimating];
    [view addSubview:self.spinner];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleControls)];
    [self.videoView addGestureRecognizer:tap];
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleGravity:)];
    doubleTap.numberOfTapsRequired = 2;
    [self.videoView addGestureRecognizer:doubleTap];
    [tap requireGestureRecognizerToFail:doubleTap];
    self.view = view;
    self.controlsShown = YES;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    CGRect bounds = self.view.bounds;
    CGFloat width = bounds.size.width;
    self.topBar.frame = CGRectMake(0, 0, width, 50);
    NSArray *top = self.topBar.subviews;
    [top[0] setFrame:CGRectMake(8, 9, 60, 32)];
    self.titleLabel.frame = CGRectMake(76, 9, width - 152, 32);
    [top[2] setFrame:CGRectMake(width - 68, 9, 60, 32)];
    self.bottomBar.frame = CGRectMake(0, bounds.size.height - 56, width, 56);
    self.playButton.frame = CGRectMake(8, 12, 64, 32);
    self.elapsedLabel.frame = CGRectMake(76, 12, 52, 32);
    self.slider.frame = CGRectMake(134, 12, width - 134 - 140, 32);
    self.remainingLabel.frame = CGRectMake(width - 134, 12, 58, 32);
    [self.bottomBar.subviews.lastObject setFrame:CGRectMake(width - 72, 12, 64, 32)];
    self.spinner.center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
}

#pragma mark - Life

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationFade];
    if (!self.displayLink) {
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(willResign) name:UIApplicationWillResignActiveNotification object:nil];
    [center addObserver:self selector:@selector(didBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    [self scheduleHide];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationFade];
}

- (void)willResign {
    // iOS stops GL in the background. The sound goes on.
    self.displayLink.paused = YES;
    [self.engine setVideoEnabled:NO];
    [self.videoView releaseGL];
}

- (void)didBecomeActive {
    [self.engine setVideoEnabled:YES];
    self.displayLink.paused = NO;
}

- (void)done {
    double position = [self.engine position];
    double duration = self.engine.duration;
    ZLLog(@"software player closes at %.1f of %.1f s, %lu frames dropped", position, duration,
          (unsigned long)self.engine.droppedFrames);
    [self.displayLink invalidate];
    self.displayLink = nil;
    [self.hideTimer invalidate];
    [self.engine close];
    [self.videoView releaseGL];
    void (^onClose)(double, double) = self.onClose;
    [self.presentingViewController dismissViewControllerAnimated:YES completion:^{
        if (onClose) onClose(position, duration);
    }];
}

#pragma mark - Display

- (void)tick {
    ZLVideoFrame *frame = [self.engine frameToShow];
    if (frame) [self.videoView showFrame:frame];
    if (!self.controlsShown || self.dragging) return;
    double position = [self.engine position];
    double duration = self.engine.duration;
    self.elapsedLabel.text = ZLTimeText(position);
    self.remainingLabel.text = duration > 0 ? [@"-" stringByAppendingString:ZLTimeText(duration - position)] : @"Live";
    if (duration > 0) self.slider.value = (float)(position / duration);
}

- (void)engineDidChangeState:(ZLPlayerEngine *)engine {
    if (engine.buffering && !engine.paused) [self.spinner startAnimating];
    else [self.spinner stopAnimating];
    [self.playButton setTitle:engine.paused ? @"Play" : @"Pause" forState:UIControlStateNormal];
}

- (void)engineDidEnd:(ZLPlayerEngine *)engine {
    [self done];
}

- (void)engine:(ZLPlayerEngine *)engine didFail:(NSError *)error {
    [[[UIAlertView alloc] initWithTitle:@"The video stopped" message:error.localizedDescription delegate:nil
                      cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    [self done];
}

#pragma mark - Controls

- (void)togglePause {
    [self.engine setPaused:!self.engine.paused];
    [self scheduleHide];
}

- (void)toggleGravity:(id)sender {
    self.videoView.gravity = self.videoView.gravity == ZLVideoGravityFit ? ZLVideoGravityFill : ZLVideoGravityFit;
    UIButton *button = self.topBar.subviews[2];
    [button setTitle:self.videoView.gravity == ZLVideoGravityFit ? @"Fit" : @"Fill" forState:UIControlStateNormal];
    [self scheduleHide];
}

- (void)toggleControls {
    [self setControlsShown:!self.controlsShown animated:YES];
    if (self.controlsShown) [self scheduleHide];
}

- (void)setControlsShown:(BOOL)shown animated:(BOOL)animated {
    _controlsShown = shown;
    [UIView animateWithDuration:animated ? 0.25 : 0 animations:^{
        self.topBar.alpha = shown ? 1 : 0;
        self.bottomBar.alpha = shown ? 1 : 0;
    }];
}

- (void)scheduleHide {
    [self.hideTimer invalidate];
    self.hideTimer = [NSTimer scheduledTimerWithTimeInterval:4 target:self selector:@selector(hideControls) userInfo:nil repeats:NO];
}

- (void)hideControls {
    if (self.dragging || self.engine.paused) return;
    [self setControlsShown:NO animated:YES];
}

- (void)sliderStarted {
    self.dragging = YES;
    [self.hideTimer invalidate];
}

- (void)sliderMoved {
    double duration = self.engine.duration;
    self.elapsedLabel.text = ZLTimeText(self.slider.value * duration);
    self.remainingLabel.text = [@"-" stringByAppendingString:ZLTimeText(duration - self.slider.value * duration)];
}

- (void)sliderEnded {
    self.dragging = NO;
    [self.engine seekTo:self.slider.value * self.engine.duration];
    [self scheduleHide];
}

- (void)chooseAudio {
    NSArray *tracks = self.engine.info.audioTracks;
    if (tracks.count < 2) {
        [[[UIAlertView alloc] initWithTitle:@"One audio track" message:@"This video has no other audio track."
                                   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        return;
    }
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Audio" delegate:self cancelButtonTitle:nil
                                         destructiveButtonTitle:nil otherButtonTitles:nil];
    for (ZLTrack *track in tracks) {
        NSString *label = track.index == self.engine.audioIndex ? [@"Now: " stringByAppendingString:[track label]] : [track label];
        [sheet addButtonWithTitle:label];
    }
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
    self.audioChoices = tracks;
    [sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    if (index == sheet.cancelButtonIndex || index >= (NSInteger)self.audioChoices.count) return;
    ZLTrack *track = self.audioChoices[(NSUInteger)index];
    [self.engine selectAudioIndex:track.index];
}

@end
