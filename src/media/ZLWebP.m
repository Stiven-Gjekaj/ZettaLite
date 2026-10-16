#import "ZLWebP.h"
#include <libavcodec/avcodec.h>
#include <libswscale/swscale.h>

BOOL ZLIsWebP(NSData *data) {
    const uint8_t *bytes = data.bytes;
    return data.length > 12 && memcmp(bytes, "RIFF", 4) == 0 && memcmp(bytes + 8, "WEBP", 4) == 0;
}

static void ZLFreePixels(void *info, const void *data, size_t size) {
    free((void *)data);
}

CGImageRef ZLCreateImageFromWebP(NSData *data, CGFloat pixels) {
    const AVCodec *codec = avcodec_find_decoder(AV_CODEC_ID_WEBP);
    if (!codec || !ZLIsWebP(data)) return NULL;
    AVCodecContext *decoder = avcodec_alloc_context3(codec);
    decoder->thread_count = 1;
    CGImageRef image = NULL;
    AVPacket *packet = av_packet_alloc();
    AVFrame *frame = av_frame_alloc();
    if (avcodec_open2(decoder, codec, NULL) >= 0 && av_new_packet(packet, (int)data.length) >= 0) {
        memcpy(packet->data, data.bytes, data.length);
        if (avcodec_send_packet(decoder, packet) >= 0 && avcodec_receive_frame(decoder, frame) >= 0) {
            int width = frame->width, height = frame->height;
            double scale = MIN(1.0, pixels / MAX(width, height));
            int outWidth = MAX(1, (int)(width * scale)), outHeight = MAX(1, (int)(height * scale));
            struct SwsContext *scaler = sws_getContext(width, height, frame->format, outWidth, outHeight, AV_PIX_FMT_BGRA,
                                                       SWS_BILINEAR, NULL, NULL, NULL);
            if (scaler) {
                size_t stride = (size_t)outWidth * 4;
                uint8_t *buffer = malloc(stride * (size_t)outHeight);
                uint8_t *planes[1] = {buffer};
                int strides[1] = {(int)stride};
                sws_scale(scaler, (const uint8_t *const *)frame->data, frame->linesize, 0, height, planes, strides);
                sws_freeContext(scaler);
                CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, buffer, stride * (size_t)outHeight, ZLFreePixels);
                CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
                image = CGImageCreate((size_t)outWidth, (size_t)outHeight, 8, 32, stride, space,
                                      kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little, provider, NULL, false,
                                      kCGRenderingIntentDefault);
                CGColorSpaceRelease(space);
                CGDataProviderRelease(provider);
            }
        }
    }
    av_frame_free(&frame);
    av_packet_free(&packet);
    avcodec_free_context(&decoder);
    return image;
}
