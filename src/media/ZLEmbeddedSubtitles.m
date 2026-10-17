#import "ZLEmbeddedSubtitles.h"

// A cue with no duration shows for this time.
static const double ZLDefaultCueSeconds = 4;

BOOL ZLIsTextSubtitleCodec(enum AVCodecID codec) {
    return codec == AV_CODEC_ID_SUBRIP || codec == AV_CODEC_ID_TEXT || codec == AV_CODEC_ID_WEBVTT ||
           codec == AV_CODEC_ID_MOV_TEXT || codec == AV_CODEC_ID_ASS || codec == AV_CODEC_ID_SSA;
}

@interface ZLEmbeddedSubtitles ()
@property (nonatomic) AVFormatContext *context;
@property (nonatomic) double origin;
@property (nonatomic, strong) NSDictionary *lists;
@end

@implementation ZLEmbeddedSubtitles

- (instancetype)initWithContext:(AVFormatContext *)context origin:(double)origin {
    if ((self = [super init])) {
        _context = context;
        _origin = origin;
        NSMutableDictionary *lists = [NSMutableDictionary dictionary];
        for (unsigned i = 0; i < context->nb_streams; i++) {
            AVStream *stream = context->streams[i];
            if (stream->codecpar->codec_type != AVMEDIA_TYPE_SUBTITLE || !ZLIsTextSubtitleCodec(stream->codecpar->codec_id)) continue;
            stream->discard = AVDISCARD_DEFAULT;
            lists[@(i)] = [ZLCueList new];
        }
        _lists = lists;
    }
    return self;
}

- (NSArray *)indexes {
    return [self.lists.allKeys sortedArrayUsingSelector:@selector(compare:)];
}

- (ZLCueList *)cuesOfStream:(int)index {
    return self.lists[@(index)];
}

static NSString *ZLPacketString(const uint8_t *bytes, int length) {
    NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)MAX(length, 0)];
    // Some packets end with a zero byte.
    while (data.length && ((const uint8_t *)data.bytes)[data.length - 1] == 0) data = [data subdataWithRange:NSMakeRange(0, data.length - 1)];
    return ZLSubtitleText(data) ?: @"";
}

- (BOOL)takePacket:(AVPacket *)packet {
    ZLCueList *list = self.lists[@(packet->stream_index)];
    if (!list) return NO;
    AVStream *stream = self.context->streams[packet->stream_index];
    int64_t pts = packet->pts != AV_NOPTS_VALUE ? packet->pts : packet->dts;
    if (pts == AV_NOPTS_VALUE || !packet->data) return YES;
    double start = pts * av_q2d(stream->time_base) - self.origin;
    double duration = packet->duration > 0 ? packet->duration * av_q2d(stream->time_base) : ZLDefaultCueSeconds;
    NSString *text = nil;
    switch (stream->codecpar->codec_id) {
        case AV_CODEC_ID_MOV_TEXT: {
            // Two bytes of length, then the text, then style boxes.
            if (packet->size < 2) return YES;
            int length = (packet->data[0] << 8) | packet->data[1];
            text = ZLCleanCueText(ZLPacketString(packet->data + 2, MIN(length, packet->size - 2)));
            break;
        }
        case AV_CODEC_ID_ASS:
        case AV_CODEC_ID_SSA:
            text = ZLASSPacketText(ZLPacketString(packet->data, packet->size));
            break;
        default:
            text = ZLCleanCueText(ZLPacketString(packet->data, packet->size));
            break;
    }
    if (text.length) [list addCue:[ZLCue cueWithStart:start end:start + duration text:text]];
    return YES;
}

@end
