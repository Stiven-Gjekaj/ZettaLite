#import "ZLAudioEncoder.h"
#import <AudioToolbox/AudioToolbox.h>
#import "ZLInput.h"
#include <libavutil/opt.h>
#include <libswresample/swresample.h>

const int ZLAACSampleRate = 48000;
const int ZLAACFrameSize = 1024;

// Frames that a segment encodes before its start and after its end. The
// Apple encoder adds 2112 samples of priming, so it needs 4 frames before.
static const int64_t ZLLeadFrames = 4;
static const int64_t ZLTrailFrames = 2;
// A jump in the input time that is longer than this starts a new timeline.
static const int64_t ZLMaxDrift = ZLAACSampleRate / 10;

@implementation ZLEncodedPacket
@end

@interface ZLAudioEncoder ()
@property (nonatomic) AVStream *source;
@property (nonatomic) AVCodecContext *decoder;
@property (nonatomic) SwrContext *resampler;
@property (nonatomic) AVCodecParameters *outputParameters;
@property (nonatomic) AVFrame *frame;
@property (nonatomic, strong) NSMutableData *left;
@property (nonatomic, strong) NSMutableData *right;
@property (nonatomic) int64_t pcmStart;  // The sample of the first stored sample. -1 when empty.
@property (nonatomic) int64_t firstGrid;  // The first frame that the segment encodes.
@property (nonatomic) int64_t startGrid;  // The first frame that the segment keeps.
@property (nonatomic) int64_t endGrid;  // The first frame of the next segment. INT64_MAX for the last.
@property (nonatomic) BOOL lastSegment;
// The AAC encoder of Apple. It is 20 times faster than real time on the A5
// chip. The AAC encoder of FFmpeg is about as fast as real time, so it is
// only the fallback.
@property (nonatomic) AudioConverterRef converter;
@property (nonatomic) int64_t priming;
@end

@implementation ZLAudioEncoder

- (instancetype)initWithStream:(AVStream *)source error:(NSError **)error {
    if ((self = [super init])) {
        _source = source;
        _frame = av_frame_alloc();
        const AVCodec *codec = avcodec_find_decoder(source->codecpar->codec_id);
        if (!codec) {
            if (error) *error = ZLAVError(AVERROR_DECODER_NOT_FOUND, @"The app has no decoder for this audio.");
            return nil;
        }
        _decoder = avcodec_alloc_context3(codec);
        avcodec_parameters_to_context(_decoder, source->codecpar);
        _decoder->pkt_timebase = source->time_base;
        _decoder->thread_count = 1;
        int result = avcodec_open2(_decoder, codec, NULL);
        if (result < 0) {
            if (error) *error = ZLAVError(result, @"FFmpeg cannot open the audio decoder.");
            return nil;
        }
        _outputParameters = avcodec_parameters_alloc();
        if ([self openConverter]) {
            [self describeAppleOutput];
        } else {
            AVCodecContext *encoder = [self openEncoder:error];
            if (!encoder) return nil;
            avcodec_parameters_from_context(_outputParameters, encoder);
            avcodec_free_context(&encoder);
        }
        _pcmStart = -1;
    }
    return self;
}

- (void)dealloc {
    if (_converter) AudioConverterDispose(_converter);
    avcodec_free_context(&_decoder);
    swr_free(&_resampler);
    avcodec_parameters_free(&_outputParameters);
    av_frame_free(&_frame);
}

- (AVCodecContext *)openEncoder:(NSError **)error {
    const AVCodec *codec = avcodec_find_encoder(AV_CODEC_ID_AAC);
    AVCodecContext *encoder = avcodec_alloc_context3(codec);
    encoder->sample_fmt = AV_SAMPLE_FMT_FLTP;
    encoder->sample_rate = ZLAACSampleRate;
    av_channel_layout_default(&encoder->ch_layout, 2);
    encoder->bit_rate = 160000;
    encoder->time_base = (AVRational){1, ZLAACSampleRate};
    encoder->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    AVDictionary *options = NULL;
    // The fast coder keeps the A5 chip free for the video.
    av_dict_set(&options, "aac_coder", "fast", 0);
    av_dict_set(&options, "aac_tns", "0", 0);
    av_dict_set(&options, "aac_pns", "0", 0);
    av_dict_set(&options, "aac_is", "0", 0);
    int result = avcodec_open2(encoder, codec, &options);
    av_dict_free(&options);
    if (result < 0) {
        if (error) *error = ZLAVError(result, @"FFmpeg cannot open the AAC encoder.");
        avcodec_free_context(&encoder);
        return NULL;
    }
    return encoder;
}

static int64_t ZLGridAtOrAfter(double seconds) {
    return (int64_t)ceil(seconds * ZLAACSampleRate / ZLAACFrameSize - 1e-6);
}

- (BOOL)beginSegmentFrom:(double)start to:(double)end error:(NSError **)error {
    avcodec_flush_buffers(self.decoder);
    self.left = [NSMutableData data];
    self.right = [NSMutableData data];
    self.pcmStart = -1;
    self.startGrid = MAX(0, ZLGridAtOrAfter(start));
    self.firstGrid = MAX(0, self.startGrid - ZLLeadFrames);
    self.lastSegment = isinf(end);
    self.endGrid = self.lastSegment ? INT64_MAX : MAX(self.startGrid, ZLGridAtOrAfter(end));
    return YES;
}

- (double)inputStart {
    return (double)(self.firstGrid * ZLAACFrameSize) / ZLAACSampleRate;
}

- (int64_t)neededEnd {
    if (self.lastSegment) return INT64_MAX;
    return (self.endGrid + ZLTrailFrames) * ZLAACFrameSize;
}

- (int64_t)pcmEnd {
    return self.pcmStart + (int64_t)(self.left.length / sizeof(float));
}

- (BOOL)hasEnoughInput {
    return !self.lastSegment && self.pcmStart >= 0 && [self pcmEnd] >= [self neededEnd];
}

- (BOOL)addPacket:(AVPacket *)packet error:(NSError **)error {
    if (packet->pts != AV_NOPTS_VALUE) {
        double seconds = packet->pts * av_q2d(self.source->time_base);
        // A packet that starts after the needed end gives nothing to the segment.
        if (!self.lastSegment && seconds * ZLAACSampleRate > [self neededEnd] + ZLAACSampleRate / 10) return YES;
        double duration = packet->duration * av_q2d(self.source->time_base);
        if ((seconds + MAX(duration, 0.1)) * ZLAACSampleRate < self.firstGrid * ZLAACFrameSize) return YES;
    }
    int result = avcodec_send_packet(self.decoder, packet);
    if (result < 0 && result != AVERROR(EAGAIN)) return YES;  // Skip a broken packet.
    while (avcodec_receive_frame(self.decoder, self.frame) == 0) {
        [self storeFrame:self.frame];
        av_frame_unref(self.frame);
    }
    return YES;
}

- (void)storeFrame:(AVFrame *)frame {
    if (!self.resampler) {
        AVChannelLayout stereo;
        av_channel_layout_default(&stereo, 2);
        swr_alloc_set_opts2(&_resampler, &stereo, AV_SAMPLE_FMT_FLTP, ZLAACSampleRate, &frame->ch_layout,
                            frame->format, frame->sample_rate, 0, NULL);
        if (swr_init(self.resampler) < 0) {
            swr_free(&_resampler);
            return;
        }
    }
    int capacity = swr_get_out_samples(self.resampler, frame->nb_samples) + 32;
    float *outLeft = malloc(sizeof(float) * (size_t)capacity);
    float *outRight = malloc(sizeof(float) * (size_t)capacity);
    uint8_t *outputs[2] = {(uint8_t *)outLeft, (uint8_t *)outRight};
    int count = swr_convert(self.resampler, outputs, capacity, (const uint8_t **)frame->extended_data, frame->nb_samples);
    if (count > 0) {
        int64_t timestamp = frame->best_effort_timestamp;
        int64_t sample = timestamp == AV_NOPTS_VALUE ? [self pcmEnd]
                                                     : av_rescale_q(timestamp, self.source->time_base,
                                                                    (AVRational){1, ZLAACSampleRate});
        int skip = 0;
        if (self.pcmStart < 0) {
            self.pcmStart = sample;
        } else {
            int64_t expected = [self pcmEnd];
            if (sample > expected + ZLMaxDrift) {
                // A gap in the input. Fill it with silence.
                NSUInteger silence = (NSUInteger)(sample - expected) * sizeof(float);
                [self.left increaseLengthBy:silence];
                [self.right increaseLengthBy:silence];
            } else if (sample < expected - ZLMaxDrift) {
                skip = (int)MIN((int64_t)count, expected - sample);
            }
        }
        if (skip < count) {
            [self.left appendBytes:outLeft + skip length:sizeof(float) * (size_t)(count - skip)];
            [self.right appendBytes:outRight + skip length:sizeof(float) * (size_t)(count - skip)];
        }
    }
    free(outLeft);
    free(outRight);
}

- (NSArray *)finishSegment:(NSError **)error {
    NSMutableArray *packets = [NSMutableArray array];
    if (self.pcmStart < 0) return packets;
    // Flush the decoder for the last segment.
    if (self.lastSegment) {
        avcodec_send_packet(self.decoder, NULL);
        while (avcodec_receive_frame(self.decoder, self.frame) == 0) {
            [self storeFrame:self.frame];
            av_frame_unref(self.frame);
        }
    }
    if (self.converter) {
        NSArray *made = [self encodeWithApple];
        self.left = nil;
        self.right = nil;
        return made;
    }
    AVCodecContext *encoder = [self openEncoder:error];
    if (!encoder) return nil;
    int64_t lastGrid = self.lastSegment ? ([self pcmEnd] + ZLAACFrameSize - 1) / ZLAACFrameSize - 1
                                        : self.endGrid + ZLTrailFrames - 1;
    const float *left = self.left.bytes;
    const float *right = self.right.bytes;
    int64_t stored = (int64_t)(self.left.length / sizeof(float));
    AVFrame *frame = av_frame_alloc();
    AVPacket *packet = av_packet_alloc();
    int64_t keepFrom = self.startGrid * ZLAACFrameSize;
    int64_t keepTo = self.lastSegment ? INT64_MAX : self.endGrid * ZLAACFrameSize;
    for (int64_t grid = self.firstGrid; grid <= lastGrid + 1; grid++) {
        BOOL flush = grid > lastGrid;
        if (!flush) {
            frame->nb_samples = ZLAACFrameSize;
            frame->format = AV_SAMPLE_FMT_FLTP;
            frame->sample_rate = ZLAACSampleRate;
            av_channel_layout_default(&frame->ch_layout, 2);
            av_frame_get_buffer(frame, 0);
            float *outLeft = (float *)frame->data[0];
            float *outRight = (float *)frame->data[1];
            int64_t first = grid * ZLAACFrameSize - self.pcmStart;
            for (int i = 0; i < ZLAACFrameSize; i++) {
                int64_t at = first + i;
                BOOL inside = at >= 0 && at < stored;
                outLeft[i] = inside ? left[at] : 0;
                outRight[i] = inside ? right[at] : 0;
            }
            frame->pts = grid * ZLAACFrameSize;
        }
        avcodec_send_frame(encoder, flush ? NULL : frame);
        av_frame_unref(frame);
        while (avcodec_receive_packet(encoder, packet) == 0) {
            if (packet->pts >= keepFrom && packet->pts < keepTo) {
                ZLEncodedPacket *encoded = [ZLEncodedPacket new];
                encoded.pts = packet->pts;
                encoded.duration = packet->duration > 0 ? packet->duration : ZLAACFrameSize;
                encoded.data = [NSData dataWithBytes:packet->data length:(NSUInteger)packet->size];
                [packets addObject:encoded];
            }
            av_packet_unref(packet);
        }
    }
    av_frame_free(&frame);
    av_packet_free(&packet);
    avcodec_free_context(&encoder);
    self.left = nil;
    self.right = nil;
    return packets;
}

#pragma mark - The Apple encoder

- (BOOL)openConverter {
    AudioStreamBasicDescription input = {0}, output = {0};
    input.mSampleRate = ZLAACSampleRate;
    input.mFormatID = kAudioFormatLinearPCM;
    input.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    input.mBytesPerPacket = 4;
    input.mFramesPerPacket = 1;
    input.mBytesPerFrame = 4;
    input.mChannelsPerFrame = 2;
    input.mBitsPerChannel = 16;
    output.mSampleRate = ZLAACSampleRate;
    output.mFormatID = kAudioFormatMPEG4AAC;
    output.mFormatFlags = kMPEG4Object_AAC_LC;
    output.mFramesPerPacket = ZLAACFrameSize;
    output.mChannelsPerFrame = 2;
    // Pick the software encoder of Apple. It is fast enough, and the system
    // player can use the hardware codec at the same time.
    UInt32 format = kAudioFormatMPEG4AAC;
    UInt32 size = 0;
    if (AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders, sizeof(format), &format, &size) != noErr || !size) return NO;
    UInt32 count = size / sizeof(AudioClassDescription);
    AudioClassDescription *descriptions = malloc(size);
    AudioFormatGetProperty(kAudioFormatProperty_Encoders, sizeof(format), &format, &size, descriptions);
    AudioConverterRef converter = NULL;
    OSStatus status = -1;
    for (UInt32 i = 0; i < count && status != noErr; i++) {
        if (descriptions[i].mManufacturer != kAppleSoftwareAudioCodecManufacturer) continue;
        status = AudioConverterNewSpecific(&input, &output, 1, &descriptions[i], &converter);
    }
    free(descriptions);
    if (status != noErr) return NO;
    UInt32 bitrate = 160000;
    AudioConverterSetProperty(converter, kAudioConverterEncodeBitRate, sizeof(bitrate), &bitrate);
    AudioConverterPrimeInfo prime = {0, 0};
    size = sizeof(prime);
    self.priming = AudioConverterGetProperty(converter, kAudioConverterPrimeInfo, &size, &prime) == noErr && prime.leadingFrames
                       ? prime.leadingFrames
                       : 2112;
    self.converter = converter;
    return YES;
}

// AAC LC, 48 kHz, stereo. The muxer makes the ADTS headers from it.
- (void)describeAppleOutput {
    AVCodecParameters *output = self.outputParameters;
    output->codec_type = AVMEDIA_TYPE_AUDIO;
    output->codec_id = AV_CODEC_ID_AAC;
    output->profile = AV_PROFILE_AAC_LOW;
    output->sample_rate = ZLAACSampleRate;
    output->frame_size = ZLAACFrameSize;
    av_channel_layout_default(&output->ch_layout, 2);
    output->extradata = av_mallocz(2 + AV_INPUT_BUFFER_PADDING_SIZE);
    output->extradata[0] = 0x11;  // Object type 2 (LC), sample rate index 3 (48 kHz)
    output->extradata[1] = 0x90;  // 2 channels
    output->extradata_size = 2;
}

typedef struct {
    const float *left;
    const float *right;
    int64_t stored;  // The samples in left and right.
    int64_t first;  // The first sample to give, as an index into left and right.
    int64_t count;  // The samples to give.
    int64_t given;
    SInt16 *scratch;
} ZLAppleInput;

static OSStatus ZLFillPCM(AudioConverterRef converter, UInt32 *packets, AudioBufferList *data,
                          AudioStreamPacketDescription **descriptions, void *user) {
    ZLAppleInput *input = user;
    int64_t left = input->count - input->given;
    if (left <= 0) {
        *packets = 0;
        return noErr;
    }
    UInt32 count = (UInt32)MIN((int64_t)MIN(*packets, 4096u), left);
    for (UInt32 i = 0; i < count; i++) {
        int64_t at = input->first + input->given + i;
        BOOL inside = at >= 0 && at < input->stored;
        float l = inside ? input->left[at] : 0, r = inside ? input->right[at] : 0;
        input->scratch[i * 2] = (SInt16)lrintf(fmaxf(-1, fminf(1, l)) * 32767);
        input->scratch[i * 2 + 1] = (SInt16)lrintf(fmaxf(-1, fminf(1, r)) * 32767);
    }
    data->mBuffers[0].mData = input->scratch;
    data->mBuffers[0].mDataByteSize = count * 4;
    data->mBuffers[0].mNumberChannels = 2;
    input->given += count;
    *packets = count;
    return noErr;
}

// Encodes the samples of the segment with the Apple encoder. Packet i shows
// the samples from firstGrid * 1024 - priming + i * 1024. All segments use
// the same rule, so their packets meet with no gap.
- (NSArray *)encodeWithApple {
    AudioConverterReset(self.converter);
    int64_t lastGrid = self.lastSegment ? ([self pcmEnd] + ZLAACFrameSize - 1) / ZLAACFrameSize - 1
                                        : self.endGrid + ZLTrailFrames - 1;
    ZLAppleInput input;
    input.left = self.left.bytes;
    input.right = self.right.bytes;
    input.stored = (int64_t)(self.left.length / sizeof(float));
    input.first = self.firstGrid * ZLAACFrameSize - self.pcmStart;
    input.count = (lastGrid + 1 - self.firstGrid) * ZLAACFrameSize;
    input.given = 0;
    input.scratch = malloc(4096 * 4);
    int64_t offset = self.priming % ZLAACFrameSize;
    int64_t keepFrom = self.startGrid * ZLAACFrameSize - offset;
    int64_t keepTo = self.lastSegment ? INT64_MAX : self.endGrid * ZLAACFrameSize - offset;
    UInt32 maxSize = 0;
    UInt32 size = sizeof(maxSize);
    AudioConverterGetProperty(self.converter, kAudioConverterPropertyMaximumOutputPacketSize, &size, &maxSize);
    if (maxSize == 0) maxSize = 6144;
    uint8_t *buffer = malloc(maxSize);
    NSMutableArray *packets = [NSMutableArray array];
    int64_t time = self.firstGrid * ZLAACFrameSize - self.priming;
    while (YES) {
        AudioBufferList list;
        list.mNumberBuffers = 1;
        list.mBuffers[0].mNumberChannels = 2;
        list.mBuffers[0].mDataByteSize = maxSize;
        list.mBuffers[0].mData = buffer;
        UInt32 count = 1;
        AudioStreamPacketDescription description;
        OSStatus status = AudioConverterFillComplexBuffer(self.converter, ZLFillPCM, &input, &count, &list, &description);
        if (status != noErr || count == 0) break;
        if (time >= keepFrom && time < keepTo) {
            ZLEncodedPacket *packet = [ZLEncodedPacket new];
            packet.pts = time;
            packet.duration = ZLAACFrameSize;
            packet.data = [NSData dataWithBytes:buffer length:list.mBuffers[0].mDataByteSize];
            [packets addObject:packet];
        }
        time += ZLAACFrameSize;
    }
    free(buffer);
    free(input.scratch);
    return packets;
}

@end
