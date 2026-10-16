// Picks the streams of an input and the player that can play them.

#import <Foundation/Foundation.h>
#import "ZLInput.h"

typedef NS_ENUM(NSInteger, ZLRoute) {
    // The system player plays the video with its hardware decoder. FFmpeg
    // only remuxes it, and changes the audio to AAC when it must.
    ZLRouteSystem,
    // The own player decodes the video in software.
    ZLRouteSoftware,
    // The app cannot play the input.
    ZLRouteNone,
};

@interface ZLTrack : NSObject
@property (nonatomic) int index;  // The stream index in the input.
@property (nonatomic) enum AVMediaType type;
@property (nonatomic, copy) NSString *codec;  // For example "h264" or "ac3".
@property (nonatomic, copy) NSString *language;  // ISO 639-2, or nil.
@property (nonatomic, copy) NSString *title;
@property (nonatomic) int channels;
@property (nonatomic) int width;
@property (nonatomic) int height;
@property (nonatomic) int bitDepth;
@property (nonatomic) BOOL isDefault;
// A label for a picker, for example "English, AC3 5.1".
- (NSString *)label;
@end

@interface ZLMediaInfo : NSObject

@property (nonatomic, readonly) ZLRoute route;
@property (nonatomic, readonly) ZLTrack *video;  // nil for audio only.
@property (nonatomic, readonly) ZLTrack *audio;  // The track that plays.
@property (nonatomic, readonly) NSArray *audioTracks;
@property (nonatomic, readonly) NSArray *subtitleTracks;
@property (nonatomic, readonly) double duration;  // Seconds. 0 when unknown, for example live.
// YES when the system player gets the audio as it is (AAC or MP3).
@property (nonatomic, readonly) BOOL audioPassThrough;
// Why the route is ZLRouteSoftware or ZLRouteNone.
@property (nonatomic, readonly, copy) NSString *reason;

// languages is the order of the preferred audio languages, ISO 639-2.
+ (instancetype)infoForInput:(ZLInput *)input languages:(NSArray *)languages;

// YES when iOS 6 plays this audio in HLS as it is.
+ (BOOL)systemPlaysAudio:(AVCodecParameters *)codec;

@end
