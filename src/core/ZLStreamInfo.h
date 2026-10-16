// Reads the quality of a stream from its text: the resolution, HDR, the
// video and audio codecs, and the size. Addons put this in the name, the
// title, or the file name of a stream, for example
// "Film.2020.1080p.BluRay.x265.10bit.DTS-HD.MA.5.1".
// The app uses it for the badges, to hide the streams that are too heavy for
// the A5 chip, and to pick the best stream for autoplay.

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, ZLVideoCodec) {
    ZLVideoCodecUnknown,
    ZLVideoCodecH264,
    ZLVideoCodecHEVC,
    ZLVideoCodecAV1,
    ZLVideoCodecVP9,
    ZLVideoCodecMPEG4,
    ZLVideoCodecMPEG2,
};

@interface ZLStreamInfo : NSObject
@property (nonatomic) int height;  // 0 when the text does not say.
@property (nonatomic) BOOL hdr;
@property (nonatomic) BOOL dolbyVision;
@property (nonatomic) BOOL tenBit;
@property (nonatomic) ZLVideoCodec codec;
@property (nonatomic, copy) NSString *audio;  // For example "DTS" or "AC3".
@property (nonatomic) BOOL dualAudio;
@property (nonatomic) BOOL camera;  // A recording in a cinema.
@property (nonatomic) double gigabytes;  // 0 when the text does not say.

+ (instancetype)infoForText:(NSString *)text;

// YES when the system player decodes the video in hardware.
- (BOOL)hardwareDecodes;
// YES when the A5 chip cannot play it in real time, as far as the text tells.
- (BOOL)tooHeavy;
// The quality for a badge, for example "1080p" or "4K".
- (NSString *)qualityText;
// The badges, for example @[@"1080p", @"HDR", @"HEVC", @"Software"].
- (NSArray *)badges;
// A higher score is a better stream for autoplay. A heavy stream scores 0.
- (double)score;
@end
