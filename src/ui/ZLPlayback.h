// Starts the playback of a media URL. It opens the input with FFmpeg in the
// background, picks the player, and shows it. With more than one item, a
// failed item gives its place to the next one. When the certificate of a
// host fails the check, it asks the user one time.

#import <UIKit/UIKit.h>

@interface ZLPlayItem : NSObject
@property (nonatomic, strong) NSURL *URL;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSDictionary *headers;
// For example "Torrentio 1080p". The loading box shows it.
@property (nonatomic, copy) NSString *sourceName;
// The bingeGroup of the stream. The next episode prefers the same group, so
// that it comes from the same source and quality.
@property (nonatomic, copy) NSString *bingeGroup;
// The second at which the playback starts. 0 starts at the start.
@property (nonatomic) double startTime;
// The subtitles that the stream gives: dictionaries with url and lang.
@property (nonatomic, copy) NSArray *subtitles;
// The Stremio type and video ID. The player asks the subtitle addons with them.
@property (nonatomic, copy) NSString *videoType;
@property (nonatomic, copy) NSString *videoID;
// Called when the player closes, with the second where it stopped, the length,
// and YES when the media played to its end.
@property (nonatomic, copy) void (^onClose)(double position, double duration, BOOL ended);
+ (instancetype)itemWithURL:(NSURL *)url title:(NSString *)title;
@end

@interface ZLPlayback : NSObject
+ (void)play:(ZLPlayItem *)item from:(UIViewController *)controller;
// Plays the first item that works.
+ (void)playItems:(NSArray *)items from:(UIViewController *)controller;
@end
