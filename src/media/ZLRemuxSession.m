#import "ZLRemuxSession.h"
#import "ZLAudioEncoder.h"
#import "ZLTrust.h"

const double ZLSegmentSeconds = 6;

// The TS timestamps are the input timestamps plus this offset, so that no
// timestamp is negative.
static const double ZLTimestampOffset = 10;
// A keyframe with a time a little before a boundary still starts the
// segment. The index of an MP4 file holds the decode time, not the
// presentation time.
static const double ZLBoundaryTolerance = 0.05;
// The audio that a segment reads after its end, so that the audio of the
// segment is complete.
static const double ZLAudioOverrun = 0.4;
// A live playlist holds this many segments.
static const NSUInteger ZLLiveWindow = 8;
// A live playlist waits for this many segments before the player gets it.
static const NSUInteger ZLLiveStartCount = 3;

#pragma mark - Packets

// One packet of the input, with its time in seconds.
@interface ZLPacket : NSObject
@property (nonatomic) AVPacket *packet;
@property (nonatomic) double seconds;
@end

@implementation ZLPacket

+ (instancetype)packetWith:(AVPacket *)source stream:(AVStream *)stream {
    ZLPacket *packet = [ZLPacket new];
    packet.packet = av_packet_clone(source);
    int64_t time = source->pts != AV_NOPTS_VALUE ? source->pts : source->dts;
    packet.seconds = time == AV_NOPTS_VALUE ? NAN : time * av_q2d(stream->time_base);
    return packet;
}

- (void)dealloc {
    av_packet_free(&_packet);
}

@end

#pragma mark - Session

@interface ZLRemuxSession ()
@property (nonatomic, strong) ZLInput *input;
@property (nonatomic, strong) ZLMediaInfo *info;
@property (nonatomic) int videoIndex;
@property (nonatomic) int audioIndex;
@property (nonatomic, strong) ZLAudioEncoder *encoder;
@property (nonatomic) BOOL live;
@property (nonatomic, strong) dispatch_queue_t work;
@property (atomic) BOOL closed;
// VOD: the time at which each segment starts, and one more for the end.
@property (nonatomic, strong) NSArray *starts;
@property (nonatomic, strong) NSMutableDictionary *cache;
// The packets that the last segment read after its end, and the segment that
// starts with them.
@property (nonatomic, strong) NSMutableArray *carry;
@property (nonatomic) NSInteger carryIndex;
// Live: the segments in the window, their numbers, and their lengths.
@property (nonatomic, strong) NSCondition *liveCondition;
@property (nonatomic, strong) NSMutableArray *liveSegments;
@property (nonatomic, strong) NSMutableArray *liveDurations;
@property (nonatomic) NSUInteger liveFirst;
@property (nonatomic) BOOL liveEnded;
@property (nonatomic, strong) NSError *liveError;
@property (nonatomic) int64_t decodeShift;
@property (nonatomic, strong) ZLEmbeddedSubtitles *subtitles;
@end

@implementation ZLRemuxSession

- (instancetype)initWithInput:(ZLInput *)input info:(ZLMediaInfo *)info audioIndex:(int)audioIndex {
    if ((self = [super init])) {
        _input = input;
        _info = info;
        _videoIndex = info.video ? info.video.index : -1;
        _audioIndex = audioIndex >= 0 ? audioIndex : (info.audio ? info.audio.index : -1);
        _work = dispatch_queue_create("ZLRemuxSession", DISPATCH_QUEUE_SERIAL);
        _cache = [NSMutableDictionary dictionary];
        _carryIndex = -1;
        _liveCondition = [NSCondition new];
        _liveSegments = [NSMutableArray array];
        _liveDurations = [NSMutableArray array];
    }
    return self;
}

- (AVStream *)stream:(int)index {
    return index >= 0 ? self.input.context->streams[index] : NULL;
}

- (BOOL)prepare:(NSError **)error {
    AVFormatContext *context = self.input.context;
    for (unsigned i = 0; i < context->nb_streams; i++) {
        BOOL used = (int)i == self.videoIndex || (int)i == self.audioIndex;
        context->streams[i]->discard = used ? AVDISCARD_DEFAULT : AVDISCARD_ALL;
    }
    double origin = context->start_time != AV_NOPTS_VALUE ? context->start_time / (double)AV_TIME_BASE : 0;
    self.subtitles = [[ZLEmbeddedSubtitles alloc] initWithContext:context origin:origin];
    if (self.audioIndex >= 0 && ![ZLMediaInfo systemPlaysAudio:[self stream:self.audioIndex]->codecpar]) {
        self.encoder = [[ZLAudioEncoder alloc] initWithStream:[self stream:self.audioIndex] error:error];
        if (!self.encoder) return NO;
    }
    self.live = !self.input.seekable || self.info.duration <= 0;
    if (self.live) {
        [NSThread detachNewThreadSelector:@selector(readLive) toTarget:self withObject:nil];
        return YES;
    }
    // A Matroska file can keep its index (the cues) until the first seek.
    av_seek_frame(context, -1, context->start_time != AV_NOPTS_VALUE ? context->start_time : 0, AVSEEK_FLAG_BACKWARD);
    self.starts = [self segmentStarts];
    return self.starts.count >= 2;
}

// The keyframes of the index make the segments. Without an index, each
// segment is ZLSegmentSeconds long, and it starts at the first keyframe at or
// after its nominal time.
- (NSArray *)segmentStarts {
    double duration = self.info.duration;
    double origin = self.input.context->start_time != AV_NOPTS_VALUE ? self.input.context->start_time / (double)AV_TIME_BASE : 0;
    NSMutableArray *keyframes = [NSMutableArray array];
    AVStream *video = [self stream:self.videoIndex];
    if (video) {
        int count = avformat_index_get_entries_count(video);
        for (int i = 0; i < count; i++) {
            const AVIndexEntry *entry = avformat_index_get_entry(video, i);
            if (entry->flags & AVINDEX_KEYFRAME) [keyframes addObject:@(entry->timestamp * av_q2d(video->time_base) - origin)];
        }
    }
    NSMutableArray *starts = [NSMutableArray arrayWithObject:@0];
    if (keyframes.count >= 2) {
        for (NSNumber *time in keyframes) {
            if (time.doubleValue - [starts.lastObject doubleValue] >= ZLSegmentSeconds && time.doubleValue < duration) {
                [starts addObject:time];
            }
        }
    } else {
        for (double time = ZLSegmentSeconds; time < duration - 1; time += ZLSegmentSeconds) [starts addObject:@(time)];
    }
    [starts addObject:@(duration)];
    return starts;
}

- (NSUInteger)segmentCount {
    return self.starts.count ? self.starts.count - 1 : 0;
}

- (double)startOfSegment:(NSUInteger)index {
    return [self.starts[index] doubleValue];
}

- (double)durationOfSegment:(NSUInteger)index {
    return [self.starts[index + 1] doubleValue] - [self.starts[index] doubleValue];
}

#pragma mark - Playlist

- (NSData *)playlist {
    if (self.live) return [self livePlaylist];
    NSMutableString *text = [NSMutableString stringWithString:@"#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-PLAYLIST-TYPE:VOD\n"];
    double longest = 0;
    for (NSUInteger i = 0; i < self.segmentCount; i++) longest = MAX(longest, [self durationOfSegment:i]);
    [text appendFormat:@"#EXT-X-TARGETDURATION:%d\n#EXT-X-MEDIA-SEQUENCE:0\n", (int)ceil(longest)];
    for (NSUInteger i = 0; i < self.segmentCount; i++) {
        [text appendFormat:@"#EXTINF:%.3f,\n%lu.ts\n", [self durationOfSegment:i], (unsigned long)i];
    }
    [text appendString:@"#EXT-X-ENDLIST\n"];
    return [text dataUsingEncoding:NSUTF8StringEncoding];
}

#pragma mark - VOD segments

- (NSData *)segmentAtIndex:(NSUInteger)index error:(NSError **)error {
    if (self.live) return [self liveSegmentAtIndex:index];
    if (index >= self.segmentCount || self.closed) return nil;
    __block NSData *data = nil;
    __block NSError *failure = nil;
    dispatch_sync(self.work, ^{
        data = self.cache[@(index)];
        if (!data) {
            data = [self makeSegment:index error:&failure];
            if (data) [self keep:data at:index];
        }
    });
    if (!data) {
        if (error) *error = failure;
        return nil;
    }
    // Make the next segment while the player plays this one.
    NSUInteger next = index + 1;
    if (next < self.segmentCount) {
        dispatch_async(self.work, ^{
            if (self.closed || self.cache[@(next)]) return;
            NSData *made = [self makeSegment:next error:NULL];
            if (made) [self keep:made at:next];
        });
    }
    return data;
}

// Keeps the newest segments.
- (void)keep:(NSData *)data at:(NSUInteger)index {
    self.cache[@(index)] = data;
    for (NSNumber *key in self.cache.allKeys) {
        if (key.unsignedIntegerValue + 2 < index || key.unsignedIntegerValue > index + 2) [self.cache removeObjectForKey:key];
    }
}

// Reads one packet of a used stream. Returns nil at the end or on an error.
- (ZLPacket *)readPacket:(int *)result {
    AVPacket *packet = av_packet_alloc();
    while (YES) {
        *result = av_read_frame(self.input.context, packet);
        if (*result < 0) break;
        if ([self.subtitles takePacket:packet]) {
            av_packet_unref(packet);
            continue;
        }
        if (packet->stream_index == self.videoIndex || packet->stream_index == self.audioIndex) {
            ZLPacket *made = [ZLPacket packetWith:packet stream:[self stream:packet->stream_index]];
            av_packet_free(&packet);
            return made;
        }
        av_packet_unref(packet);
    }
    av_packet_free(&packet);
    return nil;
}

- (NSData *)makeSegment:(NSUInteger)index error:(NSError **)error {
    double origin = self.input.context->start_time != AV_NOPTS_VALUE ? self.input.context->start_time / (double)AV_TIME_BASE : 0;
    // The thresholds in input time. The first segment starts at the first packet.
    double startThreshold = index == 0 ? -INFINITY : [self startOfSegment:index] + origin - ZLBoundaryTolerance;
    BOOL last = index + 1 >= self.segmentCount;
    double endThreshold = last ? INFINITY : [self startOfSegment:index + 1] + origin - ZLBoundaryTolerance;

    NSMutableArray *pending = [NSMutableArray array];
    if ((NSInteger)index == self.carryIndex && self.carry) {
        [pending addObjectsFromArray:self.carry];
    } else {
        int64_t target = index == 0 ? (self.input.context->start_time != AV_NOPTS_VALUE ? self.input.context->start_time : 0)
                                    : (int64_t)((startThreshold - 1.0) * AV_TIME_BASE);
        int result = av_seek_frame(self.input.context, -1, target, AVSEEK_FLAG_BACKWARD);
        if (result < 0 && index > 0) {
            if (error) *error = ZLAVError(result, @"FFmpeg cannot seek in the media.");
            return nil;
        }
    }
    self.carry = nil;
    self.carryIndex = -1;

    BOOL hasVideo = self.videoIndex >= 0;
    BOOL started = !hasVideo;
    double videoStart = hasVideo ? NAN : MAX(startThreshold, -1e9);
    double videoEnd = hasVideo ? NAN : endThreshold;
    NSMutableArray *video = [NSMutableArray array];
    NSMutableArray *audio = [NSMutableArray array];
    NSMutableArray *carry = [NSMutableArray array];
    double lastAudio = -INFINITY;
    int result = 0;
    while (!self.closed) {
        ZLPacket *packet = nil;
        if (pending.count) {
            packet = pending.firstObject;
            [pending removeObjectAtIndex:0];
        } else {
            packet = [self readPacket:&result];
            if (!packet) break;
        }
        if (packet.packet->stream_index == self.videoIndex) {
            BOOL key = (packet.packet->flags & AV_PKT_FLAG_KEY) != 0;
            if (!started) {
                if (key && (index == 0 || packet.seconds >= startThreshold)) {
                    started = YES;
                    videoStart = packet.seconds;
                } else {
                    continue;
                }
            } else if (isnan(videoEnd) && key && packet.seconds >= endThreshold) {
                videoEnd = packet.seconds;
            }
            if (!isnan(videoEnd)) [carry addObject:packet];
            else [video addObject:packet];
        } else {
            [audio addObject:packet];
            if (!isnan(packet.seconds)) lastAudio = MAX(lastAudio, packet.seconds);
            // The next segment also needs the audio just before its start.
            double boundary = isnan(videoEnd) ? endThreshold : videoEnd;
            if (!last && packet.seconds >= boundary - 1.0) [carry addObject:packet];
        }
        // The segment is complete when the video passed its end and the
        // audio passed it by ZLAudioOverrun.
        BOOL videoDone = !hasVideo ? YES : !isnan(videoEnd);
        double end = hasVideo ? videoEnd : endThreshold;
        BOOL audioDone = self.audioIndex < 0 || lastAudio >= end + ZLAudioOverrun;
        if (!last && videoDone && audioDone) break;
    }
    if (self.closed) return nil;
    if (result < 0 && result != AVERROR_EOF && !video.count && !audio.count) {
        if (error) *error = ZLAVError(result, @"FFmpeg cannot read the media.");
        return nil;
    }
    if (!last) {
        self.carry = carry;
        self.carryIndex = (NSInteger)index + 1;
    }
    double start = hasVideo ? videoStart : startThreshold;
    double end = hasVideo ? (isnan(videoEnd) ? INFINITY : videoEnd) : endThreshold;
    if (index == 0) start = -INFINITY;
    return [self muxVideo:video audio:audio from:start to:end error:error];
}

#pragma mark - Muxing

- (NSData *)muxVideo:(NSArray *)video audio:(NSArray *)audioPackets from:(double)start to:(double)end error:(NSError **)error {
    // Keep the audio of [start, end). The first segment keeps all audio before its end.
    NSMutableArray *audio = [NSMutableArray array];
    NSArray *encoded = nil;
    if (self.audioIndex >= 0) {
        if (self.encoder) {
            double from = isinf(start) ? 0 : start;
            [self.encoder beginSegmentFrom:from to:end error:NULL];
            for (ZLPacket *packet in audioPackets) [self.encoder addPacket:packet.packet error:NULL];
            encoded = [self.encoder finishSegment:error];
        } else {
            for (ZLPacket *packet in audioPackets) {
                if (isnan(packet.seconds) || (packet.seconds >= start && packet.seconds < end)) [audio addObject:packet];
            }
        }
    }

    AVFormatContext *output = NULL;
    avformat_alloc_output_context2(&output, NULL, "mpegts", NULL);
    if (!output) {
        if (error) *error = ZLMakeError(ZLErrorMedia, @"FFmpeg has no MPEG-TS muxer.");
        return nil;
    }
    AVStream *videoOut = NULL, *audioOut = NULL;
    AVStream *videoIn = [self stream:self.videoIndex];
    AVStream *audioIn = [self stream:self.audioIndex];
    if (videoIn) {
        videoOut = avformat_new_stream(output, NULL);
        avcodec_parameters_copy(videoOut->codecpar, videoIn->codecpar);
        videoOut->codecpar->codec_tag = 0;
        videoOut->time_base = videoIn->time_base;
    }
    if (audioIn) {
        audioOut = avformat_new_stream(output, NULL);
        if (self.encoder) {
            avcodec_parameters_copy(audioOut->codecpar, self.encoder.outputParameters);
            audioOut->time_base = (AVRational){1, ZLAACSampleRate};
        } else {
            avcodec_parameters_copy(audioOut->codecpar, audioIn->codecpar);
            audioOut->time_base = audioIn->time_base;
        }
        audioOut->codecpar->codec_tag = 0;
    }
    int result = avio_open_dyn_buf(&output->pb);
    AVDictionary *options = NULL;
    av_dict_set(&options, "mpegts_copyts", "1", 0);
    if (result >= 0) result = avformat_write_header(output, &options);
    av_dict_free(&options);
    if (result < 0) {
        if (output->pb) {
            uint8_t *bytes = NULL;
            avio_close_dyn_buf(output->pb, &bytes);
            av_free(bytes);
        }
        avformat_free_context(output);
        if (error) *error = ZLAVError(result, @"FFmpeg cannot start the MPEG-TS segment.");
        return nil;
    }

    [self fillDecodeTimes:video];
    AVPacket *packet = av_packet_alloc();
    for (ZLPacket *item in video) {
        av_packet_ref(packet, item.packet);
        [self write:packet from:videoIn->time_base to:videoOut output:output];
    }
    for (ZLPacket *item in audio) {
        av_packet_ref(packet, item.packet);
        [self write:packet from:audioIn->time_base to:audioOut output:output];
    }
    for (ZLEncodedPacket *item in encoded) {
        av_new_packet(packet, (int)item.data.length);
        memcpy(packet->data, item.data.bytes, item.data.length);
        packet->pts = packet->dts = item.pts;
        packet->duration = item.duration;
        packet->flags |= AV_PKT_FLAG_KEY;
        [self write:packet from:(AVRational){1, ZLAACSampleRate} to:audioOut output:output];
    }
    av_packet_free(&packet);
    av_write_trailer(output);
    uint8_t *bytes = NULL;
    int size = avio_close_dyn_buf(output->pb, &bytes);
    NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)MAX(size, 0)];
    av_free(bytes);
    avformat_free_context(output);
    return data;
}

// A Matroska file gives no decode time for H.264 with B-frames. The muxer
// needs it. The decode times are the sorted presentation times, moved back
// so that no frame decodes after it shows. The shift only grows, so that the
// decode times stay in order across segments.
- (void)fillDecodeTimes:(NSArray *)video {
    BOOL missing = NO;
    for (ZLPacket *item in video) {
        if (item.packet->dts == AV_NOPTS_VALUE && item.packet->pts != AV_NOPTS_VALUE) missing = YES;
    }
    if (!missing) return;
    NSMutableArray *times = [NSMutableArray array];
    for (ZLPacket *item in video) {
        if (item.packet->pts != AV_NOPTS_VALUE) [times addObject:@(item.packet->pts)];
    }
    [times sortUsingSelector:@selector(compare:)];
    int64_t shift = self.decodeShift;
    NSUInteger k = 0;
    for (ZLPacket *item in video) {
        if (item.packet->pts == AV_NOPTS_VALUE) continue;
        shift = MAX(shift, [times[k++] longLongValue] - item.packet->pts);
    }
    self.decodeShift = shift;
    k = 0;
    for (ZLPacket *item in video) {
        if (item.packet->pts == AV_NOPTS_VALUE) continue;
        item.packet->dts = [times[k++] longLongValue] - shift;
    }
}

// Writes one packet with the offset. It takes the reference of packet.
- (void)write:(AVPacket *)packet from:(AVRational)timeBase to:(AVStream *)stream output:(AVFormatContext *)output {
    int64_t offset = av_rescale_q((int64_t)(ZLTimestampOffset * AV_TIME_BASE), AV_TIME_BASE_Q, timeBase);
    if (packet->pts != AV_NOPTS_VALUE) packet->pts += offset;
    if (packet->dts != AV_NOPTS_VALUE) packet->dts += offset;
    av_packet_rescale_ts(packet, timeBase, stream->time_base);
    packet->stream_index = stream->index;
    packet->pos = -1;
    av_interleaved_write_frame(output, packet);
    av_packet_unref(packet);
}

#pragma mark - Live

- (void)readLive {
    @autoreleasepool {
        NSMutableArray *video = [NSMutableArray array];
        NSMutableArray *audio = [NSMutableArray array];
        BOOL hasVideo = self.videoIndex >= 0;
        double start = NAN;
        int result = 0;
        while (!self.closed) {
            @autoreleasepool {
                ZLPacket *packet = [self readPacket:&result];
                if (!packet) break;
                BOOL isVideo = packet.packet->stream_index == self.videoIndex;
                BOOL key = (packet.packet->flags & AV_PKT_FLAG_KEY) != 0;
                // The first segment starts at a keyframe.
                if (isnan(start)) {
                    if ((hasVideo && !(isVideo && key)) || isnan(packet.seconds)) continue;
                    start = packet.seconds;
                }
                BOOL boundary = hasVideo ? (isVideo && key) : YES;
                if (boundary && !isnan(packet.seconds) && packet.seconds - start >= ZLSegmentSeconds) {
                    [self finishLive:video audio:audio from:start to:packet.seconds];
                    // The encoder needs the audio just before the boundary.
                    NSMutableArray *keep = [NSMutableArray array];
                    for (ZLPacket *item in audio) {
                        if (item.seconds >= packet.seconds - 1.0) [keep addObject:item];
                    }
                    video = [NSMutableArray array];
                    audio = keep;
                    start = packet.seconds;
                }
                [(isVideo ? video : audio) addObject:packet];
            }
        }
        if (!self.closed && (video.count || audio.count) && !isnan(start)) {
            [self finishLive:video audio:audio from:start to:INFINITY];
        }
        [self.liveCondition lock];
        self.liveEnded = YES;
        if (result < 0 && result != AVERROR_EOF && !self.liveSegments.count) {
            self.liveError = ZLAVError(result, @"FFmpeg cannot read the live stream.");
        }
        [self.liveCondition broadcast];
        [self.liveCondition unlock];
    }
}

- (void)finishLive:(NSArray *)video audio:(NSArray *)audio from:(double)start to:(double)end {
    NSData *data = [self muxVideo:video audio:audio from:start to:end error:NULL];
    if (!data) return;
    [self.liveCondition lock];
    [self.liveSegments addObject:data];
    [self.liveDurations addObject:@(isinf(end) ? ZLSegmentSeconds : end - start)];
    while (self.liveSegments.count > ZLLiveWindow) {
        [self.liveSegments removeObjectAtIndex:0];
        [self.liveDurations removeObjectAtIndex:0];
        self.liveFirst++;
    }
    [self.liveCondition broadcast];
    [self.liveCondition unlock];
}

- (NSData *)livePlaylist {
    [self.liveCondition lock];
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:40];
    while (!self.liveEnded && self.liveFirst + self.liveSegments.count < ZLLiveStartCount && !self.closed) {
        if (![self.liveCondition waitUntilDate:until]) break;
    }
    NSMutableString *text = [NSMutableString stringWithString:@"#EXTM3U\n#EXT-X-VERSION:3\n"];
    double longest = ZLSegmentSeconds;
    for (NSNumber *duration in self.liveDurations) longest = MAX(longest, duration.doubleValue);
    [text appendFormat:@"#EXT-X-TARGETDURATION:%d\n#EXT-X-MEDIA-SEQUENCE:%lu\n", (int)ceil(longest),
                       (unsigned long)self.liveFirst];
    for (NSUInteger i = 0; i < self.liveSegments.count; i++) {
        [text appendFormat:@"#EXTINF:%.3f,\n%lu.ts\n", [self.liveDurations[i] doubleValue], (unsigned long)(self.liveFirst + i)];
    }
    if (self.liveEnded) [text appendString:@"#EXT-X-ENDLIST\n"];
    [self.liveCondition unlock];
    return [text dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSData *)liveSegmentAtIndex:(NSUInteger)index {
    [self.liveCondition lock];
    NSData *data = nil;
    if (index >= self.liveFirst && index < self.liveFirst + self.liveSegments.count) {
        data = self.liveSegments[index - self.liveFirst];
    }
    [self.liveCondition unlock];
    return data;
}

#pragma mark -

- (void)close {
    if (self.closed) return;
    self.closed = YES;
    [self.input cancel];
    [self.liveCondition lock];
    [self.liveCondition broadcast];
    [self.liveCondition unlock];
    ZLInput *input = self.input;
    dispatch_async(self.work, ^{
        // The live reader can still use the input. Wait until it stops.
        [self.liveCondition lock];
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:5];
        while (self.live && !self.liveEnded) {
            if (![self.liveCondition waitUntilDate:until]) break;
        }
        [self.liveCondition unlock];
        self.carry = nil;
        [input close];
    });
}

@end
