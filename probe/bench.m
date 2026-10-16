// bench: measure the decode speed of FFmpeg on the phone. For each file it
// decodes all video frames on 2 threads, and prints the frames per second,
// also with the loop filter off. For audio it decodes all samples and
// encodes them to stereo AAC, and prints the speed as a multiple of real time.
// Usage: bench FILE...

#import <Foundation/Foundation.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/opt.h>
#include <libswresample/swresample.h>

static double Now(void) {
    return [NSDate timeIntervalSinceReferenceDate];
}

static void BenchVideo(const char *path, int skipLoop) {
    AVFormatContext *context = NULL;
    if (avformat_open_input(&context, path, NULL, NULL) < 0) return;
    avformat_find_stream_info(context, NULL);
    int index = av_find_best_stream(context, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
    if (index < 0) {
        avformat_close_input(&context);
        return;
    }
    AVStream *stream = context->streams[index];
    const AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
    AVCodecContext *decoder = avcodec_alloc_context3(codec);
    avcodec_parameters_to_context(decoder, stream->codecpar);
    decoder->thread_count = 2;
    decoder->thread_type = FF_THREAD_FRAME | FF_THREAD_SLICE;
    if (skipLoop) decoder->skip_loop_filter = AVDISCARD_ALL;
    if (avcodec_open2(decoder, codec, NULL) < 0) {
        printf("%-20s cannot open the decoder %s\n", strrchr(path, '/') ? strrchr(path, '/') + 1 : path, codec ? codec->name : "?");
        avformat_close_input(&context);
        return;
    }
    AVPacket *packet = av_packet_alloc();
    AVFrame *frame = av_frame_alloc();
    int frames = 0;
    double start = Now();
    while (av_read_frame(context, packet) >= 0) {
        if (packet->stream_index == index) {
            avcodec_send_packet(decoder, packet);
            while (avcodec_receive_frame(decoder, frame) == 0) frames++;
        }
        av_packet_unref(packet);
    }
    avcodec_send_packet(decoder, NULL);
    while (avcodec_receive_frame(decoder, frame) == 0) frames++;
    double seconds = Now() - start;
    double media = frames / av_q2d(stream->avg_frame_rate);
    printf("%-20s %s %dx%d %s: %d frames in %.2f s = %.1f fps (%.2fx real time)\n",
           strrchr(path, '/') ? strrchr(path, '/') + 1 : path, codec->name, decoder->width, decoder->height,
           skipLoop ? "no loop filter" : "full", frames, seconds, frames / seconds, media / seconds);
    av_frame_free(&frame);
    av_packet_free(&packet);
    avcodec_free_context(&decoder);
    avformat_close_input(&context);
}

static void BenchAudio(const char *path) {
    AVFormatContext *context = NULL;
    if (avformat_open_input(&context, path, NULL, NULL) < 0) return;
    avformat_find_stream_info(context, NULL);
    int index = av_find_best_stream(context, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
    if (index < 0) {
        avformat_close_input(&context);
        return;
    }
    AVStream *stream = context->streams[index];
    const AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
    AVCodecContext *decoder = avcodec_alloc_context3(codec);
    avcodec_parameters_to_context(decoder, stream->codecpar);
    avcodec_open2(decoder, codec, NULL);
    const AVCodec *aac = avcodec_find_encoder(AV_CODEC_ID_AAC);
    AVCodecContext *encoder = avcodec_alloc_context3(aac);
    encoder->sample_fmt = AV_SAMPLE_FMT_FLTP;
    encoder->sample_rate = 48000;
    av_channel_layout_default(&encoder->ch_layout, 2);
    encoder->bit_rate = 160000;
    encoder->time_base = (AVRational){1, 48000};
    AVDictionary *options = NULL;
    av_dict_set(&options, "aac_coder", "fast", 0);
    avcodec_open2(encoder, aac, &options);
    av_dict_free(&options);
    SwrContext *swr = NULL;
    AVPacket *packet = av_packet_alloc();
    AVPacket *out = av_packet_alloc();
    AVFrame *frame = av_frame_alloc();
    AVFrame *pcm = av_frame_alloc();
    double decodeTime = 0, encodeTime = 0;
    int64_t samples = 0;
    float *left = malloc(sizeof(float) * 48000 * 4), *right = malloc(sizeof(float) * 48000 * 4);
    int stored = 0;
    while (av_read_frame(context, packet) >= 0) {
        if (packet->stream_index == index) {
            double t = Now();
            avcodec_send_packet(decoder, packet);
            while (avcodec_receive_frame(decoder, frame) == 0) {
                if (!swr) {
                    AVChannelLayout stereo;
                    av_channel_layout_default(&stereo, 2);
                    swr_alloc_set_opts2(&swr, &stereo, AV_SAMPLE_FMT_FLTP, 48000, &frame->ch_layout, frame->format,
                                        frame->sample_rate, 0, NULL);
                    swr_init(swr);
                }
                uint8_t *outputs[2] = {(uint8_t *)(left + stored), (uint8_t *)(right + stored)};
                int count = swr_convert(swr, outputs, 48000 * 4 - stored, (const uint8_t **)frame->extended_data, frame->nb_samples);
                if (count > 0) stored += count;
            }
            decodeTime += Now() - t;
            t = Now();
            while (stored >= 1024) {
                pcm->nb_samples = 1024;
                pcm->format = AV_SAMPLE_FMT_FLTP;
                pcm->sample_rate = 48000;
                av_channel_layout_default(&pcm->ch_layout, 2);
                av_frame_get_buffer(pcm, 0);
                memcpy(pcm->data[0], left, 4096);
                memcpy(pcm->data[1], right, 4096);
                memmove(left, left + 1024, sizeof(float) * (size_t)(stored - 1024));
                memmove(right, right + 1024, sizeof(float) * (size_t)(stored - 1024));
                stored -= 1024;
                pcm->pts = samples;
                samples += 1024;
                avcodec_send_frame(encoder, pcm);
                av_frame_unref(pcm);
                while (avcodec_receive_packet(encoder, out) == 0) av_packet_unref(out);
            }
            encodeTime += Now() - t;
        }
        av_packet_unref(packet);
    }
    double media = samples / 48000.0;
    printf("%-20s %s %d ch: decode %.1fx real time, AAC encode %.1fx real time\n",
           strrchr(path, '/') ? strrchr(path, '/') + 1 : path, codec->name, decoder->ch_layout.nb_channels,
           media / decodeTime, media / encodeTime);
    free(left);
    free(right);
    avformat_close_input(&context);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        av_log_set_level(AV_LOG_ERROR);
        for (int i = 1; i < argc; i++) {
            BenchVideo(argv[i], 0);
            BenchVideo(argv[i], 1);
            BenchAudio(argv[i]);
        }
    }
    return 0;
}
