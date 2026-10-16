// ffprobe: test that the FFmpeg dylib loads on iOS 6, and list the media
// streams of a file or URL.
// Usage: ffprobe [FILE]

#import <Foundation/Foundation.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>

int main(int argc, char **argv) {
    @autoreleasepool {
        printf("avformat %s, avcodec %s\n", AV_STRINGIFY(LIBAVFORMAT_VERSION), AV_STRINGIFY(LIBAVCODEC_VERSION));
        const char *names[] = {"h264", "hevc", "vp9", "av1", "mpeg2video", "mpeg4", "ac3", "eac3", "dca", "truehd", "opus", "vorbis", "flac", "aac"};
        for (unsigned i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
            printf("  decoder %-10s %s\n", names[i], avcodec_find_decoder_by_name(names[i]) ? "yes" : "no");
        }
        if (argc < 2) return 0;
        AVFormatContext *context = NULL;
        int result = avformat_open_input(&context, argv[1], NULL, NULL);
        if (result < 0) {
            printf("open failed: %s\n", av_err2str(result));
            return 1;
        }
        avformat_find_stream_info(context, NULL);
        av_dump_format(context, 0, argv[1], 0);
        avformat_close_input(&context);
    }
    return 0;
}
