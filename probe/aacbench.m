// aacbench: measure the AAC encoders on the phone. It encodes 30 seconds of
// stereo sound at 48 kHz with the FFmpeg encoder (with options) and with the
// hardware AudioConverter of iOS, and prints the speed as a multiple of real time.
// Usage: aacbench

#import <AudioToolbox/AudioToolbox.h>
#import <Foundation/Foundation.h>
#include <libavcodec/avcodec.h>

static const int Seconds = 30;
static const int Rate = 48000;

static double FFmpegSpeed(const char *options) {
    const AVCodec *aac = avcodec_find_encoder(AV_CODEC_ID_AAC);
    AVCodecContext *encoder = avcodec_alloc_context3(aac);
    encoder->sample_fmt = AV_SAMPLE_FMT_FLTP;
    encoder->sample_rate = Rate;
    av_channel_layout_default(&encoder->ch_layout, 2);
    encoder->bit_rate = atoi(getenv("RATE") ?: "128000");
    encoder->time_base = (AVRational){1, Rate};
    AVDictionary *dict = NULL;
    av_dict_parse_string(&dict, options, "=", ",", 0);
    if (avcodec_open2(encoder, aac, &dict) < 0) return 0;
    av_dict_free(&dict);
    AVFrame *frame = av_frame_alloc();
    AVPacket *packet = av_packet_alloc();
    NSDate *start = [NSDate date];
    for (int i = 0; i < Seconds * Rate / 1024; i++) {
        frame->nb_samples = 1024;
        frame->format = AV_SAMPLE_FMT_FLTP;
        frame->sample_rate = Rate;
        av_channel_layout_default(&frame->ch_layout, 2);
        av_frame_get_buffer(frame, 0);
        for (int c = 0; c < 2; c++) {
            float *data = (float *)frame->data[c];
            for (int s = 0; s < 1024; s++) data[s] = 0.3f * sinf((i * 1024 + s) * 0.0576f * (c + 1));
        }
        frame->pts = i * 1024;
        avcodec_send_frame(encoder, frame);
        av_frame_unref(frame);
        while (avcodec_receive_packet(encoder, packet) == 0) av_packet_unref(packet);
    }
    double seconds = -[start timeIntervalSinceNow];
    avcodec_free_context(&encoder);
    return Seconds / seconds;
}

typedef struct {
    SInt16 *samples;
    UInt32 frames;
    UInt32 used;
} Input;

static OSStatus Fill(AudioConverterRef converter, UInt32 *packets, AudioBufferList *data,
                     AudioStreamPacketDescription **descriptions, void *user) {
    Input *input = user;
    UInt32 left = input->frames - input->used;
    if (left == 0) {
        *packets = 0;
        return noErr;
    }
    UInt32 count = MIN(*packets, left);
    data->mBuffers[0].mData = input->samples + input->used * 2;
    data->mBuffers[0].mDataByteSize = count * 4;
    data->mBuffers[0].mNumberChannels = 2;
    input->used += count;
    *packets = count;
    return noErr;
}

static double HardwareSpeed(void) {
    AudioStreamBasicDescription in = {0}, out = {0};
    in.mSampleRate = Rate;
    in.mFormatID = kAudioFormatLinearPCM;
    in.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    in.mBytesPerPacket = 4;
    in.mFramesPerPacket = 1;
    in.mBytesPerFrame = 4;
    in.mChannelsPerFrame = 2;
    in.mBitsPerChannel = 16;
    out.mSampleRate = Rate;
    out.mFormatID = kAudioFormatMPEG4AAC;
    out.mFormatFlags = kMPEG4Object_AAC_LC;
    out.mFramesPerPacket = 1024;
    out.mChannelsPerFrame = 2;
    UInt32 size = 0;
    UInt32 format = kAudioFormatMPEG4AAC;
    AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders, sizeof(format), &format, &size);
    UInt32 count = size / sizeof(AudioClassDescription);
    AudioClassDescription descriptions[count];
    AudioFormatGetProperty(kAudioFormatProperty_Encoders, sizeof(format), &format, &size, descriptions);
    for (UInt32 i = 0; i < count; i++) {
        printf("encoder %u: manufacturer %c%c%c%c\n", (unsigned)i, (char)(descriptions[i].mManufacturer >> 24),
               (char)(descriptions[i].mManufacturer >> 16), (char)(descriptions[i].mManufacturer >> 8),
               (char)descriptions[i].mManufacturer);
    }
    AudioConverterRef converter = NULL;
    OSStatus status = -1;
    for (UInt32 i = 0; i < count && status != noErr; i++) {
        status = AudioConverterNewSpecific(&in, &out, 1, &descriptions[i], &converter);
        printf("AudioConverterNewSpecific %u: %d\n", (unsigned)i, (int)status);
    }
    if (status != noErr) return 0;
    UInt32 bitrate = 128000;
    status = AudioConverterSetProperty(converter, kAudioConverterEncodeBitRate, sizeof(bitrate), &bitrate);
    printf("bitrate status %d\n", (int)status);
    Input input;
    input.frames = Seconds * Rate;
    input.used = 0;
    input.samples = malloc(input.frames * 4);
    for (UInt32 s = 0; s < input.frames; s++) {
        input.samples[s * 2] = (SInt16)(9000 * sinf(s * 0.0576f));
        input.samples[s * 2 + 1] = (SInt16)(9000 * sinf(s * 0.1152f));
    }
    UInt32 maxSize = 0;
    size = sizeof(maxSize);
    AudioConverterGetProperty(converter, kAudioConverterPropertyMaximumOutputPacketSize, &size, &maxSize);
    uint8_t *buffer = malloc(maxSize);
    int packets = 0;
    NSDate *start = [NSDate date];
    while (YES) {
        AudioBufferList list;
        list.mNumberBuffers = 1;
        list.mBuffers[0].mNumberChannels = 2;
        list.mBuffers[0].mDataByteSize = maxSize;
        list.mBuffers[0].mData = buffer;
        UInt32 packetCount = 1;
        AudioStreamPacketDescription description;
        status = AudioConverterFillComplexBuffer(converter, Fill, &input, &packetCount, &list, &description);
        if (status != noErr || packetCount == 0) break;
        packets++;
    }
    double seconds = -[start timeIntervalSinceNow];
    printf("hardware: %d packets, status %d\n", packets, (int)status);
    AudioConverterDispose(converter);
    return Seconds / seconds;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        printf("ffmpeg fast: %.1fx\n", FFmpegSpeed("aac_coder=fast"));
        printf("ffmpeg fast, no tools: %.1fx\n", FFmpegSpeed("aac_coder=fast,aac_tns=0,aac_ms=0,aac_is=0,aac_pns=0"));
        printf("hardware: %.1fx\n", HardwareSpeed());
    }
    return 0;
}
