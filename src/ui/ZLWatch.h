// Plays films and episodes with the library: it starts where the video
// stopped, it keeps the progress when the player closes, and at the end of an
// episode it counts down to the next one, from the same source if it can.

#import <UIKit/UIKit.h>
#import "ZLMeta.h"

@interface ZLWatch : NSObject

// The play items of the streams from index on, at most 5, with the library hooks.
+ (NSArray *)itemsForStreams:(NSArray *)streams from:(NSUInteger)index meta:(ZLMeta *)meta episode:(ZLEpisode *)episode;

// Plays the best stream at once. When no stream fits the phone, it shows the
// stream picker. bingeGroup puts the streams of that group first.
+ (void)autoplay:(ZLMeta *)meta episode:(ZLEpisode *)episode bingeGroup:(NSString *)bingeGroup
            from:(UIViewController *)controller;

@end
