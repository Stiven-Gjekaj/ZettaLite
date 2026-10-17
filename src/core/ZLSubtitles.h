// Subtitles as a list of cues. It reads SRT and WebVTT files, and the text of
// the subtitle packets of a media file: SubRip, WebVTT, mov_text, and ASS.
// The text keeps the line breaks and loses the styles.

#import <Foundation/Foundation.h>

@interface ZLCue : NSObject
@property (nonatomic) double start;  // Seconds.
@property (nonatomic) double end;
@property (nonatomic, copy) NSString *text;
+ (instancetype)cueWithStart:(double)start end:(double)end text:(NSString *)text;
@end

// Reads an SRT or a WebVTT file. The cues are in the order of their start.
NSArray *ZLParseSubtitles(NSString *text);

// Decodes the bytes of a subtitle file: UTF-8, UTF-16 with a byte order
// mark, or Windows-1252.
NSString *ZLSubtitleText(NSData *data);

// Removes the styles from the text of one cue: HTML tags such as <i>, ASS
// override blocks such as {\an8}, and the "\N" line breaks of ASS.
NSString *ZLCleanCueText(NSString *text);

// The text of an ASS packet in a media file. The packet has 8 fields before
// the text: ReadOrder, Layer, Style, Name, MarginL, MarginR, MarginV, Effect.
NSString *ZLASSPacketText(NSString *packet);

// A list of cues that grows while a media file plays. It is safe to use
// from more than one thread.
@interface ZLCueList : NSObject
- (instancetype)initWithCues:(NSArray *)cues;
- (void)addCue:(ZLCue *)cue;
- (NSUInteger)count;
// The text of the cues that show at this second, or nil.
- (NSString *)textAt:(double)seconds;
@end
