// Starts the playback of a media URL. It opens the input with FFmpeg in the
// background, picks the player, and shows it. When iOS 6 does not trust the
// certificate of a host, it asks the user one time.

#import <UIKit/UIKit.h>

@interface ZLPlayItem : NSObject
@property (nonatomic, strong) NSURL *URL;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSDictionary *headers;
// The second at which the playback starts. 0 starts at the start.
@property (nonatomic) double startTime;
+ (instancetype)itemWithURL:(NSURL *)url title:(NSString *)title;
@end

@interface ZLPlayback : NSObject
+ (void)play:(ZLPlayItem *)item from:(UIViewController *)controller;
@end
