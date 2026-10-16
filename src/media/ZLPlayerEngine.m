#import "ZLPlayerEngine.h"
#import <AudioToolbox/AudioToolbox.h>
#import "ZLLog.h"
#import "ZLTrust.h"
#include <libavcodec/avcodec.h>
#include <libavutil/imgutils.h>
#include <libswresample/swresample.h>
#include <libswscale/swscale.h>
#include <mach/mach_time.h>

static const int ZLOutputRate = 48000;
// The frames that the video thread decodes ahead of the display.
static const NSUInteger ZLMaxFrames = 4;
// The bytes of packets that the reader keeps ahead of the decoders.
static const NSUInteger ZLMaxPacketBytes = 8 * 1024 * 1024;
// The ring buffer of the sound holds 3 seconds of stereo samples.
static const int ZLRingSamples = ZLOutputRate * 3;
enum { ZLQueueBuffers = 3 };
static const int ZLQueueBufferFrames = 2048;
// The playback waits until this much sound is ready after a seek or a stall.
static const double ZLBufferSeconds = 0.5;
// A frame that is later than this does not show.
static const double ZLLateLimit = 0.5;

static double ZLNow(void) {
    static mach_timebase_info_data_t timebase;
    if (timebase.denom == 0) mach_timebase_info(&timebase);
    return (double)mach_absolute_time() * timebase.numer / timebase.denom / 1e9;
}

#pragma mark - Frames and packets

@interface ZLVideoFrame ()
@property (nonatomic) int width;
@property (nonatomic) int height;
@property (nonatomic) double time;
@property (nonatomic, strong) NSData *luma;
@property (nonatomic, strong) NSData *blue;
@property (nonatomic, strong) NSData *red;
@property (nonatomic) BOOL fullRange;
@property (nonatomic) BOOL hd;
@property (nonatomic) double aspect;
@end

@implementation ZLVideoFrame
@end

@interface ZLEnginePacket : NSObject
@property (nonatomic) AVPacket *packet;
@property (nonatomic) int serial;
@end

@implementation ZLEnginePacket

- (void)dealloc {
    av_packet_free(&_packet);
}

@end

// The audio time of one run of samples: the sample index where the run
// starts in the AudioQueue, and the media second of that sample.
typedef struct {
    int64_t index;
    double time;
} ZLAnchor;

#pragma mark - Engine

@interface ZLPlayerEngine () {
    int16_t *_ring;  // Interleaved stereo.
    int _ringRead;
    int _ringFill;  // Samples (one per channel pair) in the ring.
    double _ringTime;  // The media second of the next sample to read.
    BOOL _ringNewRun;
    int64_t _samplesGiven;
    ZLAnchor _anchors[16];
    int _anchorCount;
    AudioQueueRef _queue;
    AudioQueueBufferRef _buffers[ZLQueueBuffers];
}
@property (nonatomic, strong) ZLInput *input;
@property (nonatomic, strong) ZLMediaInfo *info;
@property (nonatomic) int videoIndex;
@property (nonatomic) int audioIndex;
@property (nonatomic) AVCodecContext *videoDecoder;
@property (nonatomic) AVCodecContext *audioDecoder;
@property (nonatomic) SwrContext *resampler;
@property (nonatomic) struct SwsContext *scaler;
@property (nonatomic) double origin;  // The start time of the input, in seconds.
@property (nonatomic) double duration;

@property (nonatomic, strong) NSCondition *packetLock;
@property (nonatomic, strong) NSMutableArray *videoPackets;
@property (nonatomic, strong) NSMutableArray *audioPackets;
@property (nonatomic) NSUInteger packetBytes;
@property (nonatomic) int serial;
@property (nonatomic) BOOL seekRequested;
@property (nonatomic) double seekTime;
@property (nonatomic) BOOL demuxEnded;
@property (nonatomic) int newAudioIndex;

@property (nonatomic, strong) NSCondition *frameLock;
@property (nonatomic, strong) NSMutableArray *frames;
@property (nonatomic) double dropBefore;  // Frames and sound before this second do not play, after a seek.
@property (nonatomic) NSUInteger droppedFrames;

// The ring buffer of the sound. The AudioQueue reads it, so nothing slow
// happens while this lock is held.
@property (nonatomic, strong) NSCondition *audioLock;
// The audio decoder. A change of the audio track replaces it.
@property (nonatomic, strong) NSLock *decoderLock;
@property (nonatomic) int lastShownSerial;

@property (atomic) BOOL closing;
@property (nonatomic) BOOL videoEnabled;
@property (nonatomic) BOOL paused;
@property (nonatomic) BOOL buffering;
@property (nonatomic) BOOL ended;
@property (nonatomic) int runningThreads;
@property (nonatomic, strong) NSCondition *threadLock;
@property (nonatomic, strong) dispatch_source_t monitor;

// The clock without sound.
@property (nonatomic) double wallBase;  // The media second at wallStart.
@property (nonatomic) double wallStart;  // The host time, or 0 when the clock stops.
@property (nonatomic) double lastPosition;
@end

static void ZLAudioCallback(void *user, AudioQueueRef queue, AudioQueueBufferRef buffer);

@implementation ZLPlayerEngine

- (instancetype)initWithInput:(ZLInput *)input info:(ZLMediaInfo *)info {
    if ((self = [super init])) {
        _input = input;
        _info = info;
        _videoIndex = info.video ? info.video.index : -1;
        _audioIndex = info.audio ? info.audio.index : -1;
        _newAudioIndex = _audioIndex;
        _duration = info.duration;
        AVFormatContext *context = input.context;
        _origin = context->start_time != AV_NOPTS_VALUE ? context->start_time / (double)AV_TIME_BASE : 0;
        _packetLock = [NSCondition new];
        _frameLock = [NSCondition new];
        _audioLock = [NSCondition new];
        _decoderLock = [NSLock new];
        _lastShownSerial = -1;
        _threadLock = [NSCondition new];
        _videoPackets = [NSMutableArray array];
        _audioPackets = [NSMutableArray array];
        _frames = [NSMutableArray array];
        _ring = calloc((size_t)ZLRingSamples * 2, sizeof(int16_t));
        _videoEnabled = YES;
    }
    return self;
}

- (void)dealloc {
    [self close];
    free(_ring);
}

#pragma mark - Start

- (AVCodecContext *)openDecoder:(int)index threads:(int)threads error:(NSError **)error {
    AVStream *stream = self.input.context->streams[index];
    const AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
    // FFmpeg has two AV1 decoders. Its own one needs a hardware decoder.
    if (stream->codecpar->codec_id == AV_CODEC_ID_AV1) codec = avcodec_find_decoder_by_name("libdav1d") ?: codec;
    if (!codec) {
        if (error) *error = ZLAVError(AVERROR_DECODER_NOT_FOUND, @"The app has no decoder for this media.");
        return NULL;
    }
    AVCodecContext *decoder = avcodec_alloc_context3(codec);
    avcodec_parameters_to_context(decoder, stream->codecpar);
    decoder->pkt_timebase = stream->time_base;
    decoder->thread_count = threads;
    decoder->thread_type = FF_THREAD_FRAME | FF_THREAD_SLICE;
    int result = avcodec_open2(decoder, codec, NULL);
    if (result < 0) {
        if (error) *error = ZLAVError(result, @"FFmpeg cannot open the decoder.");
        avcodec_free_context(&decoder);
        return NULL;
    }
    return decoder;
}

- (BOOL)startAt:(double)seconds error:(NSError **)error {
    AVFormatContext *context = self.input.context;
    for (unsigned i = 0; i < context->nb_streams; i++) {
        BOOL used = (int)i == self.videoIndex || (int)i == self.audioIndex;
        context->streams[i]->discard = used ? AVDISCARD_DEFAULT : AVDISCARD_ALL;
    }
    if (self.videoIndex >= 0) {
        self.videoDecoder = [self openDecoder:self.videoIndex threads:2 error:error];
        if (!self.videoDecoder) return NO;
    }
    if (self.audioIndex >= 0) {
        self.audioDecoder = [self openDecoder:self.audioIndex threads:1 error:NULL];
        if (!self.audioDecoder) self.audioIndex = -1;
        else if (![self openAudioQueue]) self.audioIndex = -1;
    }
    self.newAudioIndex = self.audioIndex;
    if (seconds > 0) {
        self.seekRequested = YES;
        self.seekTime = seconds;
    }
    self.dropBefore = seconds;
    self.lastPosition = seconds;
    self.wallBase = seconds;
    self.buffering = YES;
    self.runningThreads = 0;
    [self startThread:@selector(readLoop)];
    if (self.videoIndex >= 0) [self startThread:@selector(videoLoop)];
    if (self.audioIndex >= 0) [self startThread:@selector(audioLoop)];
    [self startMonitor];
    return YES;
}

- (void)startThread:(SEL)selector {
    [self.threadLock lock];
    self.runningThreads++;
    [self.threadLock unlock];
    NSThread *thread = [[NSThread alloc] initWithTarget:self selector:selector object:nil];
    // The decoders need more stack than the default 512 KB of a thread.
    thread.stackSize = 2 * 1024 * 1024;
    [thread start];
}

- (void)threadEnded {
    [self.threadLock lock];
    self.runningThreads--;
    [self.threadLock broadcast];
    [self.threadLock unlock];
}

#pragma mark - Reader

- (void)readLoop {
    @autoreleasepool {
        AVPacket *packet = av_packet_alloc();
        while (!self.closing) {
            @autoreleasepool {
                [self.packetLock lock];
                if (self.seekRequested) {
                    double target = self.seekTime;
                    self.seekRequested = NO;
                    [self.packetLock unlock];
                    [self performSeek:target];
                    continue;
                }
                // Wait while the decoders have enough packets.
                BOOL full = self.packetBytes > ZLMaxPacketBytes &&
                            (self.videoIndex < 0 || self.videoPackets.count) && (self.audioIndex < 0 || self.audioPackets.count);
                if (full || self.demuxEnded) {
                    [self.packetLock waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
                    [self.packetLock unlock];
                    continue;
                }
                int serial = self.serial;
                [self.packetLock unlock];

                int result = av_read_frame(self.input.context, packet);
                if (result < 0) {
                    if (self.closing) break;
                    [self.packetLock lock];
                    if (self.serial == serial) self.demuxEnded = YES;
                    [self.packetLock broadcast];
                    [self.packetLock unlock];
                    if (result != AVERROR_EOF) ZLLog(@"player read: %d", result);
                    continue;
                }
                BOOL isVideo = packet->stream_index == self.videoIndex;
                BOOL isAudio = packet->stream_index == self.audioIndex;
                if (isVideo || isAudio) {
                    ZLEnginePacket *item = [ZLEnginePacket new];
                    item.packet = av_packet_clone(packet);
                    item.serial = serial;
                    [self.packetLock lock];
                    if (self.serial == serial) {
                        [isVideo ? self.videoPackets : self.audioPackets addObject:item];
                        self.packetBytes += (NSUInteger)packet->size;
                        [self.packetLock broadcast];
                    }
                    [self.packetLock unlock];
                }
                av_packet_unref(packet);
            }
        }
        av_packet_free(&packet);
        [self threadEnded];
    }
}

- (void)performSeek:(double)target {
    int64_t time = (int64_t)((target + self.origin) * AV_TIME_BASE);
    int result = av_seek_frame(self.input.context, -1, time, AVSEEK_FLAG_BACKWARD);
    if (result < 0) ZLLog(@"player seek to %.1f: %d", target, result);
    [self.packetLock lock];
    self.serial++;
    [self.videoPackets removeAllObjects];
    [self.audioPackets removeAllObjects];
    self.packetBytes = 0;
    self.demuxEnded = NO;
    if (self.newAudioIndex != self.audioIndex) [self switchAudioStream];
    [self.packetLock broadcast];
    [self.packetLock unlock];
    [self.frameLock lock];
    [self.frames removeAllObjects];
    self.dropBefore = target;
    [self.frameLock broadcast];
    [self.frameLock unlock];
    [self.audioLock lock];
    _ringRead = 0;
    _ringFill = 0;
    _ringNewRun = YES;
    _ringTime = target;
    _anchorCount = 0;
    [self.audioLock broadcast];
    [self.audioLock unlock];
    self.wallBase = target;
    self.wallStart = 0;
    self.lastPosition = target;
    self.ended = NO;
    [self setBufferingState:YES];
}

// Call with the packet lock held.
- (void)switchAudioStream {
    AVFormatContext *context = self.input.context;
    if (self.audioIndex >= 0) context->streams[self.audioIndex]->discard = AVDISCARD_ALL;
    context->streams[self.newAudioIndex]->discard = AVDISCARD_DEFAULT;
    [self.decoderLock lock];
    AVCodecContext *old = self.audioDecoder;
    self.audioDecoder = [self openDecoder:self.newAudioIndex threads:1 error:NULL];
    swr_free(&_resampler);
    avcodec_free_context(&old);
    [self.decoderLock unlock];
    self.audioIndex = self.newAudioIndex;
}

#pragma mark - Video

- (ZLEnginePacket *)nextPacketFrom:(NSMutableArray *)queue {
    [self.packetLock lock];
    while (!self.closing && queue.count == 0) {
        [self.packetLock waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    ZLEnginePacket *item = nil;
    if (queue.count) {
        item = queue.firstObject;
        [queue removeObjectAtIndex:0];
        self.packetBytes -= (NSUInteger)item.packet->size;
        [self.packetLock broadcast];
    }
    [self.packetLock unlock];
    return item;
}

- (void)videoLoop {
    @autoreleasepool {
        AVFrame *frame = av_frame_alloc();
        int serial = -1;
        BOOL needKey = NO;
        int late = 0;
        while (!self.closing) {
            @autoreleasepool {
                ZLEnginePacket *item = [self nextPacketFrom:self.videoPackets];
                if (!item) continue;
                if (item.serial != serial) {
                    avcodec_flush_buffers(self.videoDecoder);
                    serial = item.serial;
                    late = 0;
                    self.videoDecoder->skip_loop_filter = AVDISCARD_DEFAULT;
                    self.videoDecoder->skip_frame = AVDISCARD_DEFAULT;
                }
                if (!self.videoEnabled) {
                    // In the background, keep no video. Start again at a keyframe.
                    needKey = YES;
                    continue;
                }
                if (needKey) {
                    if (!(item.packet->flags & AV_PKT_FLAG_KEY)) continue;
                    avcodec_flush_buffers(self.videoDecoder);
                    needKey = NO;
                }
                if (avcodec_send_packet(self.videoDecoder, item.packet) < 0) continue;
                while (!self.closing && avcodec_receive_frame(self.videoDecoder, frame) == 0) {
                    double time = [self secondsOf:frame->best_effort_timestamp stream:self.videoIndex];
                    double now = [self position];
                    BOOL tooLate = !self.buffering && !self.paused && time < now - ZLLateLimit;
                    BOOL beforeSeek = time < self.dropBefore - 0.001;
                    if (!beforeSeek && !tooLate) [self pushFrame:frame time:time serial:serial];
                    if (tooLate) self.droppedFrames++;
                    late = tooLate ? MIN(late + 1, 40) : MAX(late - 1, 0);
                    // When the decoder falls behind, it first skips the loop
                    // filter, and then the frames that no other frame needs.
                    self.videoDecoder->skip_loop_filter = late > 2 ? AVDISCARD_ALL : AVDISCARD_DEFAULT;
                    self.videoDecoder->skip_frame = late > 12 ? AVDISCARD_NONREF : AVDISCARD_DEFAULT;
                    av_frame_unref(frame);
                }
            }
        }
        av_frame_free(&frame);
        [self threadEnded];
    }
}

- (double)secondsOf:(int64_t)timestamp stream:(int)index {
    if (timestamp == AV_NOPTS_VALUE) return [self position];
    return timestamp * av_q2d(self.input.context->streams[index]->time_base) - self.origin;
}

static NSData *ZLPackPlane(const uint8_t *source, int stride, int width, int height) {
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)(width * height)];
    uint8_t *target = data.mutableBytes;
    for (int y = 0; y < height; y++) memcpy(target + y * width, source + y * stride, (size_t)width);
    return data;
}

- (void)pushFrame:(AVFrame *)frame time:(double)time serial:(int)serial {
    int width = frame->width, height = frame->height;
    int chromaWidth = (width + 1) / 2, chromaHeight = (height + 1) / 2;
    ZLVideoFrame *made = [ZLVideoFrame new];
    made.width = width;
    made.height = height;
    made.time = time;
    made.fullRange = frame->color_range == AVCOL_RANGE_JPEG || frame->format == AV_PIX_FMT_YUVJ420P;
    made.hd = frame->colorspace == AVCOL_SPC_BT709 || (frame->colorspace == AVCOL_SPC_UNSPECIFIED && height >= 720);
    AVRational sar = frame->sample_aspect_ratio;
    double pixel = sar.num > 0 && sar.den > 0 ? av_q2d(sar) : 1;
    made.aspect = height > 0 ? width * pixel / height : 1;
    if (frame->format == AV_PIX_FMT_YUV420P || frame->format == AV_PIX_FMT_YUVJ420P) {
        made.luma = ZLPackPlane(frame->data[0], frame->linesize[0], width, height);
        made.blue = ZLPackPlane(frame->data[1], frame->linesize[1], chromaWidth, chromaHeight);
        made.red = ZLPackPlane(frame->data[2], frame->linesize[2], chromaWidth, chromaHeight);
    } else {
        // 10-bit and other formats become 8-bit 4:2:0.
        self.scaler = sws_getCachedContext(self.scaler, width, height, frame->format, width, height, AV_PIX_FMT_YUV420P,
                                           SWS_FAST_BILINEAR, NULL, NULL, NULL);
        if (!self.scaler) return;
        NSMutableData *luma = [NSMutableData dataWithLength:(NSUInteger)(width * height)];
        NSMutableData *blue = [NSMutableData dataWithLength:(NSUInteger)(chromaWidth * chromaHeight)];
        NSMutableData *red = [NSMutableData dataWithLength:(NSUInteger)(chromaWidth * chromaHeight)];
        uint8_t *planes[3] = {luma.mutableBytes, blue.mutableBytes, red.mutableBytes};
        int strides[3] = {width, chromaWidth, chromaWidth};
        sws_scale(self.scaler, (const uint8_t *const *)frame->data, frame->linesize, 0, height, planes, strides);
        made.luma = luma;
        made.blue = blue;
        made.red = red;
    }
    [self.frameLock lock];
    while (!self.closing && self.frames.count >= ZLMaxFrames && self.serial == serial) {
        [self.frameLock waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    if (self.serial == serial && !self.closing) [self.frames addObject:made];
    [self.frameLock unlock];
}

- (ZLVideoFrame *)frameToShow {
    double now = [self position];
    ZLVideoFrame *show = nil;
    [self.frameLock lock];
    // Drop the frames that a newer frame replaces.
    while (self.frames.count >= 2 && [self.frames[1] time] <= now) {
        [self.frames removeObjectAtIndex:0];
        self.droppedFrames++;
    }
    if (self.frames.count && ([self.frames[0] time] <= now + 0.01 || self.buffering || self.paused)) {
        // While the playback waits, the first frame after a seek shows at once.
        if ([self.frames[0] time] <= now + 0.01 || self.lastShownSerial != self.serial) {
            show = self.frames[0];
            [self.frames removeObjectAtIndex:0];
            self.lastShownSerial = self.serial;
        }
    }
    [self.frameLock broadcast];
    [self.frameLock unlock];
    return show;
}

#pragma mark - Audio

- (void)audioLoop {
    @autoreleasepool {
        AVFrame *frame = av_frame_alloc();
        int serial = -1;
        int16_t *converted = NULL;
        int capacity = 0;
        while (!self.closing) {
            @autoreleasepool {
                ZLEnginePacket *item = [self nextPacketFrom:self.audioPackets];
                if (!item) continue;
                [self.decoderLock lock];
                AVCodecContext *decoder = self.audioDecoder;
                if (item.serial != serial) {
                    if (decoder) avcodec_flush_buffers(decoder);
                    swr_free(&_resampler);
                    serial = item.serial;
                }
                if (!decoder || avcodec_send_packet(decoder, item.packet) < 0) {
                    [self.decoderLock unlock];
                    continue;
                }
                while (!self.closing && avcodec_receive_frame(decoder, frame) == 0) {
                    if (!self.resampler) {
                        AVChannelLayout stereo;
                        av_channel_layout_default(&stereo, 2);
                        swr_alloc_set_opts2(&_resampler, &stereo, AV_SAMPLE_FMT_S16, ZLOutputRate, &frame->ch_layout,
                                            frame->format, frame->sample_rate, 0, NULL);
                        if (swr_init(self.resampler) < 0) swr_free(&_resampler);
                    }
                    if (!self.resampler) break;
                    int needed = swr_get_out_samples(self.resampler, frame->nb_samples) + 64;
                    if (needed > capacity) {
                        capacity = needed;
                        converted = realloc(converted, (size_t)capacity * 4);
                    }
                    uint8_t *outputs[1] = {(uint8_t *)converted};
                    int count = swr_convert(self.resampler, outputs, capacity, (const uint8_t **)frame->extended_data, frame->nb_samples);
                    double time = [self secondsOf:frame->best_effort_timestamp stream:self.audioIndex];
                    av_frame_unref(frame);
                    if (count <= 0) continue;
                    // After a seek, drop the sound before the target.
                    int skip = 0;
                    if (time < self.dropBefore) {
                        skip = (int)MIN((double)count, (self.dropBefore - time) * ZLOutputRate);
                        time += skip / (double)ZLOutputRate;
                    }
                    [self writeSamples:converted + skip * 2 count:count - skip time:time serial:serial];
                }
                [self.decoderLock unlock];
            }
        }
        free(converted);
        av_frame_free(&frame);
        [self threadEnded];
    }
}

// Waits while the ring is full.
- (void)writeSamples:(const int16_t *)samples count:(int)count time:(double)time serial:(int)serial {
    [self.audioLock lock];
    while (count > 0 && !self.closing && self.serial == serial) {
        if (_ringFill == 0) {
            // A new run of sound starts at the time of its first sample.
            _ringTime = time;
            _ringNewRun = YES;
        }
        int space = ZLRingSamples - _ringFill;
        if (space == 0) {
            [self.audioLock waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
            continue;
        }
        int chunk = MIN(count, space);
        int write = (_ringRead + _ringFill) % ZLRingSamples;
        int first = MIN(chunk, ZLRingSamples - write);
        memcpy(_ring + write * 2, samples, (size_t)first * 4);
        if (chunk > first) memcpy(_ring, samples + first * 2, (size_t)(chunk - first) * 4);
        _ringFill += chunk;
        samples += chunk * 2;
        count -= chunk;
        time += chunk / (double)ZLOutputRate;
    }
    [self.audioLock unlock];
}

- (BOOL)openAudioQueue {
    AudioStreamBasicDescription format = {0};
    format.mSampleRate = ZLOutputRate;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    format.mBytesPerPacket = 4;
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = 4;
    format.mChannelsPerFrame = 2;
    format.mBitsPerChannel = 16;
    if (AudioQueueNewOutput(&format, ZLAudioCallback, (__bridge void *)self, NULL, NULL, 0, &_queue) != noErr) return NO;
    for (int i = 0; i < ZLQueueBuffers; i++) {
        if (AudioQueueAllocateBuffer(_queue, ZLQueueBufferFrames * 4, &_buffers[i]) != noErr) return NO;
        [self fillBuffer:_buffers[i]];
        AudioQueueEnqueueBuffer(_queue, _buffers[i], 0, NULL);
    }
    return YES;
}

// The AudioQueue calls this on its own thread for each empty buffer.
static void ZLAudioCallback(void *user, AudioQueueRef queue, AudioQueueBufferRef buffer) {
    ZLPlayerEngine *engine = (__bridge ZLPlayerEngine *)user;
    if (engine.closing) return;
    [engine fillBuffer:buffer];
    AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
}

- (void)fillBuffer:(AudioQueueBufferRef)buffer {
    int16_t *target = buffer->mAudioData;
    int wanted = ZLQueueBufferFrames;
    [self.audioLock lock];
    int given = MIN(wanted, self.buffering || self.paused ? 0 : _ringFill);
    if (given > 0 && _ringNewRun) {
        // Remember where this run of sound starts in the queue.
        if (_anchorCount == 16) {
            memmove(_anchors, _anchors + 1, sizeof(ZLAnchor) * 15);
            _anchorCount = 15;
        }
        _anchors[_anchorCount++] = (ZLAnchor){_samplesGiven, _ringTime};
        _ringNewRun = NO;
    }
    for (int done = 0; done < given;) {
        int chunk = MIN(given - done, ZLRingSamples - _ringRead);
        memcpy(target + done * 2, _ring + _ringRead * 2, (size_t)chunk * 4);
        _ringRead = (_ringRead + chunk) % ZLRingSamples;
        done += chunk;
    }
    _ringFill -= given;
    _ringTime += given / (double)ZLOutputRate;
    if (given < wanted) {
        memset(target + given * 2, 0, (size_t)(wanted - given) * 4);
        // The sound after the silence is a new run.
        if (given > 0 || _ringFill == 0) _ringNewRun = YES;
    }
    _samplesGiven += wanted;
    [self.audioLock broadcast];
    [self.audioLock unlock];
    buffer->mAudioDataByteSize = (UInt32)wanted * 4;
}

#pragma mark - Clock

- (double)position {
    if (self.audioIndex >= 0 && _queue) {
        AudioTimeStamp stamp;
        [self.audioLock lock];
        double position = self.lastPosition;
        if (_anchorCount > 0 && AudioQueueGetCurrentTime(_queue, NULL, &stamp, NULL) == noErr) {
            int64_t played = (int64_t)stamp.mSampleTime;
            for (int i = _anchorCount - 1; i >= 0; i--) {
                if (_anchors[i].index <= played) {
                    double time = _anchors[i].time + (played - _anchors[i].index) / (double)ZLOutputRate;
                    // The silence after the last sound does not move the clock.
                    position = MAX(self.lastPosition, MIN(time, _ringTime));
                    break;
                }
            }
        }
        self.lastPosition = position;
        [self.audioLock unlock];
        return position;
    }
    if (self.wallStart > 0) return self.wallBase + (ZLNow() - self.wallStart);
    return self.wallBase;
}

#pragma mark - State

- (double)bufferedSeconds {
    [self.audioLock lock];
    double seconds = _ringFill / (double)ZLOutputRate;
    [self.audioLock unlock];
    return seconds;
}

- (void)startMonitor {
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), NSEC_PER_SEC / 10, NSEC_PER_SEC / 50);
    __weak ZLPlayerEngine *weakSelf = self;
    dispatch_source_set_event_handler(timer, ^{ [weakSelf checkState]; });
    self.monitor = timer;
    dispatch_resume(timer);
}

// Runs 10 times a second on the main thread. It starts and stops the clock
// when the sound or the frames run out, and it finds the end.
- (void)checkState {
    if (self.closing) return;
    [self.packetLock lock];
    BOOL demuxEnded = self.demuxEnded;
    BOOL packetsLeft = self.videoPackets.count || self.audioPackets.count;
    [self.packetLock unlock];
    [self.frameLock lock];
    NSUInteger frames = self.frames.count;
    [self.frameLock unlock];
    BOOL hasAudio = self.audioIndex >= 0;
    double buffered = hasAudio ? [self bufferedSeconds] : 0;
    BOOL ready = hasAudio ? (buffered >= ZLBufferSeconds || (demuxEnded && !packetsLeft))
                          : (frames >= 2 || (demuxEnded && !packetsLeft));
    BOOL empty = hasAudio ? buffered == 0 : frames == 0;
    if (self.buffering && ready) {
        [self setBufferingState:NO];
    } else if (!self.buffering && empty && !demuxEnded) {
        [self setBufferingState:YES];
    }
    if (demuxEnded && !packetsLeft && frames == 0 && (!hasAudio || buffered == 0) && !self.ended) {
        self.ended = YES;
        [self.delegate engineDidEnd:self];
    }
}

- (void)setBufferingState:(BOOL)buffering {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self setBufferingState:buffering]; });
        return;
    }
    BOOL changed = self.buffering != buffering;
    self.buffering = buffering;
    [self updateClock];
    if (changed) [self.delegate engineDidChangeState:self];
}

- (void)updateClock {
    BOOL running = !self.paused && !self.buffering && !self.closing;
    if (_queue) {
        if (running) AudioQueueStart(_queue, NULL);
        else AudioQueuePause(_queue);
    }
    if (running && self.wallStart == 0) {
        self.wallStart = ZLNow();
    } else if (!running && self.wallStart > 0) {
        self.wallBase += ZLNow() - self.wallStart;
        self.wallStart = 0;
    }
}

- (void)setPaused:(BOOL)paused {
    _paused = paused;
    [self updateClock];
    [self.delegate engineDidChangeState:self];
}

- (void)seekTo:(double)seconds {
    if (self.duration > 0) seconds = MAX(0, MIN(seconds, self.duration - 0.5));
    [self.packetLock lock];
    self.seekRequested = YES;
    self.seekTime = seconds;
    [self.packetLock broadcast];
    [self.packetLock unlock];
    self.lastPosition = seconds;
    self.wallBase = seconds;
}

- (void)selectAudioIndex:(int)index {
    if (index == self.audioIndex || !_queue) return;
    [self.packetLock lock];
    self.newAudioIndex = index;
    [self.packetLock unlock];
    [self seekTo:[self position]];
}

- (void)setVideoEnabled:(BOOL)enabled {
    _videoEnabled = enabled;
    if (!enabled) {
        [self.frameLock lock];
        [self.frames removeAllObjects];
        [self.frameLock broadcast];
        [self.frameLock unlock];
    }
}

- (void)close {
    if (self.closing) return;
    self.closing = YES;
    if (self.monitor) dispatch_source_cancel(self.monitor);
    self.monitor = nil;
    [self.input cancel];
    for (NSCondition *lock in @[ self.packetLock, self.frameLock, self.audioLock ]) {
        [lock lock];
        [lock broadcast];
        [lock unlock];
    }
    // Wait for the threads, so that no thread uses a decoder after it is free.
    [self.threadLock lock];
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:5];
    while (self.runningThreads > 0) {
        if (![self.threadLock waitUntilDate:until]) break;
    }
    [self.threadLock unlock];
    if (_queue) {
        AudioQueueStop(_queue, true);
        AudioQueueDispose(_queue, true);
        _queue = NULL;
    }
    avcodec_free_context(&_videoDecoder);
    avcodec_free_context(&_audioDecoder);
    swr_free(&_resampler);
    sws_freeContext(_scaler);
    _scaler = NULL;
    [self.input close];
}

@end
