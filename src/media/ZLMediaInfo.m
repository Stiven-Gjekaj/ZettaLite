#import "ZLMediaInfo.h"
#include <libavutil/pixdesc.h>

@implementation ZLTrack

- (NSString *)label {
    NSMutableArray *parts = [NSMutableArray array];
    NSString *language = self.language.length ? [[NSLocale currentLocale] displayNameForKey:NSLocaleLanguageCode
                                                                                     value:self.language]
                                              : nil;
    if (self.title.length) [parts addObject:self.title];
    else if (language.length) [parts addObject:language.capitalizedString];
    else if (self.language.length) [parts addObject:self.language];
    NSString *codec = self.codec.uppercaseString;
    if (self.type == AVMEDIA_TYPE_AUDIO && self.channels > 2) {
        codec = [codec stringByAppendingFormat:@" %d.1", self.channels - 1];
    }
    if (codec.length) [parts addObject:codec];
    return parts.count ? [parts componentsJoinedByString:@", "] : [NSString stringWithFormat:@"Track %d", self.index];
}

@end

@interface ZLMediaInfo ()
@property (nonatomic) ZLRoute route;
@property (nonatomic, strong) ZLTrack *video;
@property (nonatomic, strong) ZLTrack *audio;
@property (nonatomic, strong) NSArray *audioTracks;
@property (nonatomic, strong) NSArray *subtitleTracks;
@property (nonatomic) double duration;
@property (nonatomic) BOOL audioPassThrough;
@property (nonatomic, copy) NSString *reason;
@end

@implementation ZLMediaInfo

static NSString *ZLTag(AVStream *stream, const char *key) {
    AVDictionaryEntry *entry = av_dict_get(stream->metadata, key, NULL, 0);
    return entry ? [NSString stringWithUTF8String:entry->value] : nil;
}

static ZLTrack *ZLTrackFor(AVStream *stream) {
    AVCodecParameters *codec = stream->codecpar;
    ZLTrack *track = [ZLTrack new];
    track.index = stream->index;
    track.type = codec->codec_type;
    track.codec = [NSString stringWithUTF8String:avcodec_get_name(codec->codec_id)];
    track.language = ZLTag(stream, "language");
    if ([track.language isEqualToString:@"und"]) track.language = nil;
    track.title = ZLTag(stream, "title");
    track.channels = codec->ch_layout.nb_channels;
    track.width = codec->width;
    track.height = codec->height;
    const AVPixFmtDescriptor *format = av_pix_fmt_desc_get(codec->format);
    track.bitDepth = format ? format->comp[0].depth : 8;
    track.isDefault = (stream->disposition & AV_DISPOSITION_DEFAULT) != 0;
    return track;
}

+ (BOOL)systemPlaysAudio:(AVCodecParameters *)codec {
    if (codec->ch_layout.nb_channels > 2) return NO;
    if (codec->codec_id == AV_CODEC_ID_MP3) return YES;
    // AAC LC and HE-AAC. iOS 6 does not play AAC Main or LTP.
    return codec->codec_id == AV_CODEC_ID_AAC &&
           (codec->profile == AV_PROFILE_UNKNOWN || codec->profile == AV_PROFILE_AAC_LOW ||
            codec->profile == AV_PROFILE_AAC_HE || codec->profile == AV_PROFILE_AAC_HE_V2) &&
           codec->sample_rate <= 48000;
}

// The A5 chip decodes H.264 up to High profile, level 4.1, 8 bits, 1080p.
static NSString *ZLWhyNotHardware(AVCodecParameters *codec, ZLTrack *track) {
    if (codec->codec_id != AV_CODEC_ID_H264) return [NSString stringWithFormat:@"The phone has no hardware decoder for %@.", track.codec.uppercaseString];
    if (track.bitDepth > 8) return @"The phone has no hardware decoder for 10-bit H.264.";
    if (codec->profile == AV_PROFILE_H264_HIGH_422 || codec->profile == AV_PROFILE_H264_HIGH_444_PREDICTIVE) return @"The phone has no hardware decoder for this H.264 profile.";
    if (codec->width > 1920 || codec->height > 1088) return @"The video is larger than 1080p.";
    return nil;
}

+ (instancetype)infoForInput:(ZLInput *)input languages:(NSArray *)languages {
    ZLMediaInfo *info = [ZLMediaInfo new];
    AVFormatContext *context = input.context;
    info.duration = context->duration > 0 ? context->duration / (double)AV_TIME_BASE : 0;
    NSMutableArray *audio = [NSMutableArray array];
    NSMutableArray *subtitles = [NSMutableArray array];
    for (unsigned i = 0; i < context->nb_streams; i++) {
        AVStream *stream = context->streams[i];
        enum AVMediaType type = stream->codecpar->codec_type;
        if (type == AVMEDIA_TYPE_AUDIO && stream->codecpar->codec_id != AV_CODEC_ID_NONE) {
            [audio addObject:ZLTrackFor(stream)];
        } else if (type == AVMEDIA_TYPE_SUBTITLE) {
            [subtitles addObject:ZLTrackFor(stream)];
        }
    }
    info.audioTracks = audio;
    info.subtitleTracks = subtitles;

    int videoIndex = av_find_best_stream(context, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
    if (videoIndex >= 0 && (context->streams[videoIndex]->disposition & AV_DISPOSITION_ATTACHED_PIC)) videoIndex = -1;
    if (videoIndex >= 0) info.video = ZLTrackFor(context->streams[videoIndex]);

    // The audio: the first preferred language, then the default, then the best.
    ZLTrack *chosen = nil;
    for (NSString *language in languages) {
        for (ZLTrack *track in audio) {
            if ([track.language isEqualToString:language]) {
                chosen = track;
                break;
            }
        }
        if (chosen) break;
    }
    if (!chosen) {
        int best = av_find_best_stream(context, AVMEDIA_TYPE_AUDIO, -1, videoIndex, NULL, 0);
        for (ZLTrack *track in audio) {
            if (track.index == best) chosen = track;
        }
    }
    info.audio = chosen;
    if (chosen) info.audioPassThrough = [self systemPlaysAudio:context->streams[chosen.index]->codecpar];

    if (!info.video && !info.audio) {
        info.route = ZLRouteNone;
        info.reason = @"The media has no video and no audio that the app can read.";
    } else if (!info.video) {
        info.route = ZLRouteSystem;
    } else {
        NSString *why = ZLWhyNotHardware(context->streams[videoIndex]->codecpar, info.video);
        info.route = why ? ZLRouteSoftware : ZLRouteSystem;
        info.reason = why;
        if (why && !avcodec_find_decoder(context->streams[videoIndex]->codecpar->codec_id)) {
            info.route = ZLRouteNone;
            info.reason = [NSString stringWithFormat:@"The app has no decoder for %@.", info.video.codec.uppercaseString];
        }
    }
    return info;
}

@end
