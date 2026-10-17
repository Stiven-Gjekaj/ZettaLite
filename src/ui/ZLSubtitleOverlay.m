#import "ZLSubtitleOverlay.h"
#import <QuartzCore/QuartzCore.h>
#import "ZLAddonManager.h"
#import "ZLHTTPStream.h"
#import "ZLLog.h"
#import "ZLSettings.h"
#import "ZLTheme.h"

// One choice in the picker.
@interface ZLSubtitleChoice : NSObject
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *language;  // ISO 639-2, or nil.
@property (nonatomic) int streamIndex;  // For the subtitles in the file, else -1.
@property (nonatomic, strong) NSURL *URL;  // For the subtitles of an addon.
@property (nonatomic, strong) ZLCueList *cues;  // nil until an addon file loads.
@end

@implementation ZLSubtitleChoice
@end

static NSString *ZLLanguageName(NSString *code) {
    if (!code.length) return nil;
    NSString *name = [[NSLocale currentLocale] displayNameForKey:NSLocaleLanguageCode value:code];
    return name.length ? name.capitalizedString : code;
}

// The view of the overlay. It puts the label at the bottom at each layout,
// so that a rotation moves it.
@interface ZLSubtitleView : UIView
@property (nonatomic, strong) UILabel *label;
@property (nonatomic) CGFloat bottomInset;
@end

@implementation ZLSubtitleView

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    double size = [ZLSettings shared].subtitleSize;
    if (size <= 0) size = 18;
    // A wide screen gets bigger letters.
    if (bounds.size.width > bounds.size.height) size *= 1.15;
    self.label.font = ZLBoldFont((CGFloat)size);
    CGFloat width = bounds.size.width - 24;
    CGSize fit = [self.label sizeThatFits:CGSizeMake(width, bounds.size.height / 2)];
    self.label.frame = CGRectMake(12, bounds.size.height - self.bottomInset - fit.height, width, fit.height);
}

@end

@interface ZLSubtitleOverlay () <UIActionSheetDelegate>
@property (nonatomic, strong) UIView *view;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) NSMutableArray *choices;
@property (nonatomic, strong) ZLSubtitleChoice *current;
@property (nonatomic, strong) ZLEmbeddedSubtitles *embedded;
// YES after the viewer picks, so that a late addon answer does not change it.
@property (nonatomic) BOOL picked;
@property (nonatomic, copy) NSString *shownText;
@end

@implementation ZLSubtitleOverlay

- (instancetype)initWithItem:(ZLPlayItem *)item info:(ZLMediaInfo *)info embedded:(ZLEmbeddedSubtitles *)embedded {
    if ((self = [super init])) {
        _embedded = embedded;
        _choices = [NSMutableArray array];
        [self makeView];
        self.bottomInset = 60;
        NSArray *indexes = embedded.indexes;
        for (ZLTrack *track in info.subtitleTracks) {
            if (![indexes containsObject:@(track.index)]) continue;
            ZLSubtitleChoice *choice = [ZLSubtitleChoice new];
            choice.streamIndex = track.index;
            choice.language = track.language;
            choice.label = [NSString stringWithFormat:@"%@ (in the file)", track.title.length ? track.title : (ZLLanguageName(track.language) ?: @"Unknown")];
            choice.cues = [embedded cuesOfStream:track.index];
            [_choices addObject:choice];
        }
        [self addAddonSubtitles:item.subtitles];
        [self pickPreferred];
        if (item.videoType.length && item.videoID.length) {
            __weak ZLSubtitleOverlay *weakSelf = self;
            [[ZLAddonManager shared] loadSubtitles:item.videoType identifier:item.videoID completion:^(NSArray *subtitles) {
                [weakSelf addAddonSubtitles:subtitles];
                [weakSelf pickPreferred];
            }];
        }
    }
    return self;
}

- (void)makeView {
    self.view = [[ZLSubtitleView alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view.userInteractionEnabled = NO;
    self.view.backgroundColor = [UIColor clearColor];
    self.label = [UILabel new];
    self.label.backgroundColor = [UIColor clearColor];
    self.label.textColor = [UIColor whiteColor];
    self.label.textAlignment = NSTextAlignmentCenter;
    self.label.numberOfLines = 0;
    // A dark glow around the letters keeps them clear on a light picture.
    self.label.layer.shadowColor = [UIColor blackColor].CGColor;
    self.label.layer.shadowOffset = CGSizeZero;
    self.label.layer.shadowRadius = 2;
    self.label.layer.shadowOpacity = 1;
    [self.view addSubview:self.label];
    ((ZLSubtitleView *)self.view).label = self.label;
}

- (CGFloat)bottomInset {
    return ((ZLSubtitleView *)self.view).bottomInset;
}

- (void)setBottomInset:(CGFloat)bottomInset {
    ((ZLSubtitleView *)self.view).bottomInset = bottomInset;
    [self.view setNeedsLayout];
}

- (void)addAddonSubtitles:(NSArray *)subtitles {
    NSMutableSet *known = [NSMutableSet set];
    for (ZLSubtitleChoice *choice in self.choices) {
        if (choice.URL) [known addObject:choice.URL.absoluteString];
    }
    for (NSDictionary *item in subtitles) {
        if (![item isKindOfClass:[NSDictionary class]] || ![item[@"url"] isKindOfClass:[NSString class]]) continue;
        NSURL *url = [NSURL URLWithString:item[@"url"]];
        if (!url || [known containsObject:url.absoluteString]) continue;
        [known addObject:url.absoluteString];
        ZLSubtitleChoice *choice = [ZLSubtitleChoice new];
        choice.streamIndex = -1;
        choice.URL = url;
        NSString *lang = [item[@"lang"] isKindOfClass:[NSString class]] ? item[@"lang"] : nil;
        choice.language = lang.length == 2 ? ZLLanguage3(lang) : lang.lowercaseString;
        // Number the subtitles of one language: "English 2".
        NSString *name = ZLLanguageName(choice.language) ?: @"Unknown";
        NSUInteger same = 1;
        for (ZLSubtitleChoice *other in self.choices) {
            if (other.URL && [other.language isEqualToString:choice.language]) same++;
        }
        choice.label = same > 1 ? [NSString stringWithFormat:@"%@ %lu", name, (unsigned long)same] : name;
        [self.choices addObject:choice];
    }
}

- (void)pickPreferred {
    NSString *language = [ZLSettings shared].subtitleLanguage;
    if (self.picked || self.current || !language.length) return;
    // The subtitles in the file first. They match the video.
    for (ZLSubtitleChoice *choice in self.choices) {
        if ([choice.language isEqualToString:language]) {
            [self choose:choice];
            return;
        }
    }
}

- (NSString *)currentLabel {
    return self.current.label;
}

- (void)choose:(ZLSubtitleChoice *)choice {
    self.current = choice;
    self.shownText = nil;
    self.label.text = nil;
    if (!choice || choice.cues) return;
    NSURL *url = choice.URL;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        NSData *data = [ZLHTTPStream fetch:url headers:nil finalURL:NULL error:&error];
        NSArray *cues = ZLParseSubtitles(ZLSubtitleText(data) ?: @"");
        ZLLog(@"subtitles %@: %lu cues %@", url.lastPathComponent, (unsigned long)cues.count, error ? error.localizedDescription : @"");
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!cues.count) return;
            choice.cues = [[ZLCueList alloc] initWithCues:cues];
        });
    });
}

- (void)showAt:(double)seconds {
    NSString *text = isnan(seconds) ? nil : [self.current.cues textAt:seconds];
    if (text == self.shownText || [text isEqualToString:self.shownText]) return;
    self.shownText = text;
    self.label.text = text;
    [self.view setNeedsLayout];
}

#pragma mark - Picker

- (void)showPickerInView:(UIView *)view {
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Subtitles" delegate:self cancelButtonTitle:nil
                                         destructiveButtonTitle:nil otherButtonTitles:nil];
    [sheet addButtonWithTitle:self.current ? @"Off" : @"Now: Off"];
    for (ZLSubtitleChoice *choice in self.choices) {
        [sheet addButtonWithTitle:choice == self.current ? [@"Now: " stringByAppendingString:choice.label] : choice.label];
    }
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
    [sheet showInView:view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    if (index == sheet.cancelButtonIndex || index < 0) return;
    self.picked = YES;
    [self choose:index == 0 ? nil : self.choices[(NSUInteger)index - 1]];
}

@end
