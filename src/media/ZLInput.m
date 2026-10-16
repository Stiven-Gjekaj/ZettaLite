#import "ZLInput.h"
#import "ZLHTTPStream.h"
#import "ZLLog.h"
#include <libavutil/opt.h>

static const int ZLIOBufferSize = 64 * 1024;

NSError *ZLAVError(int code, NSString *text) {
    char reason[AV_ERROR_MAX_STRING_SIZE] = {0};
    av_strerror(code, reason, sizeof(reason));
    NSString *message = [NSString stringWithFormat:@"%@ (%s)", text, reason];
    return [NSError errorWithDomain:ZLErrorDomain code:ZLErrorMedia userInfo:@{ NSLocalizedDescriptionKey: message }];
}

@interface ZLInput ()
@property (nonatomic) AVFormatContext *context;
@property (nonatomic, strong) NSURL *URL;
@property (nonatomic, copy) NSDictionary *headers;
@property (nonatomic) BOOL seekable;
@property (nonatomic, strong) NSMutableArray *streams;
@property (nonatomic, strong) NSError *streamError;
@property (atomic) BOOL cancelled;
- (AVIOContext *)openIO:(NSURL *)url error:(NSError **)error;
- (void)closeIO:(AVIOContext *)io;
- (BOOL)ownsIO:(AVIOContext *)io;
@end

#pragma mark - AVIO callbacks

static int ZLReadPacket(void *opaque, uint8_t *buffer, int size) {
    ZLHTTPStream *stream = (__bridge ZLHTTPStream *)opaque;
    NSError *error = nil;
    NSInteger count = [stream read:buffer length:(NSUInteger)size error:&error];
    if (count == 0) return AVERROR_EOF;
    if (count < 0) return error.code == ZLErrorCancelled ? AVERROR_EXIT : AVERROR(EIO);
    return (int)count;
}

static int64_t ZLSeek(void *opaque, int64_t offset, int whence) {
    ZLHTTPStream *stream = (__bridge ZLHTTPStream *)opaque;
    if (whence & AVSEEK_SIZE) return stream.length >= 0 ? stream.length : AVERROR(ENOSYS);
    whence &= ~AVSEEK_FORCE;
    int64_t target;
    if (whence == SEEK_SET) target = offset;
    else if (whence == SEEK_CUR) target = stream.position + offset;
    else if (whence == SEEK_END && stream.length >= 0) target = stream.length + offset;
    else return AVERROR(EINVAL);
    return [stream seekTo:target error:NULL] ? target : AVERROR(EIO);
}

static int ZLInterrupt(void *opaque) {
    ZLInput *input = (__bridge ZLInput *)opaque;
    return input.cancelled;
}

// The HLS and DASH demuxers open each playlist and segment through this hook.
static int ZLIOOpen(AVFormatContext *context, AVIOContext **pb, const char *url, int flags, AVDictionary **options) {
    ZLInput *input = (__bridge ZLInput *)context->opaque;
    if (!input || (flags & AVIO_FLAG_WRITE)) return AVERROR(EPERM);
    NSURL *target = [NSURL URLWithString:[NSString stringWithUTF8String:url]];
    if (!target) return AVERROR(EINVAL);
    NSError *error = nil;
    AVIOContext *io = [input openIO:target error:&error];
    if (!io) {
        input.streamError = error;
        return error.code == ZLErrorHTTPStatus ? AVERROR_HTTP_NOT_FOUND : AVERROR(EIO);
    }
    *pb = io;
    return 0;
}

static int ZLIOClose(AVFormatContext *context, AVIOContext *pb) {
    ZLInput *input = (__bridge ZLInput *)context->opaque;
    // A context that the app did not open goes back to FFmpeg.
    if (!input || ![input ownsIO:pb]) return avio_close(pb);
    [input closeIO:pb];
    return 0;
}

#pragma mark -

@implementation ZLInput

+ (instancetype)openURL:(NSURL *)url headers:(NSDictionary *)headers error:(NSError **)error {
    ZLInput *input = [ZLInput new];
    input.URL = url;
    input.headers = headers;
    input.streams = [NSMutableArray array];
    return [input open:error] ? input : nil;
}

- (void)dealloc {
    [self close];
}

- (BOOL)open:(NSError **)error {
    AVFormatContext *context = avformat_alloc_context();
    context->opaque = (__bridge void *)self;
    context->interrupt_callback.callback = ZLInterrupt;
    context->interrupt_callback.opaque = (__bridge void *)self;
    // A file opens with the file code of FFmpeg. A URL opens through the hook.
    if (!self.URL.isFileURL) {
        context->io_open = ZLIOOpen;
        context->io_close2 = ZLIOClose;
    }
    NSString *name = self.URL.absoluteString;
    AVIOContext *io = NULL;
    if (!self.URL.isFileURL) {
        io = [self openIO:self.URL error:error];
        if (!io) {
            avformat_free_context(context);
            return NO;
        }
        ZLHTTPStream *stream = self.streams.lastObject;
        self.seekable = stream.seekable;
        context->pb = io;
        // A playlist resolves its relative links against the URL after redirects.
        name = stream.finalURL.absoluteString ?: name;
    } else {
        name = self.URL.path;
        self.seekable = YES;
    }
    AVDictionary *options = NULL;
    // A short probe keeps the start fast on the A5 chip.
    av_dict_set(&options, "probesize", "2000000", 0);
    av_dict_set(&options, "analyzeduration", "3000000", 0);
    ZLLog(@"avformat_open_input %@", name);
    int result = avformat_open_input(&context, name.UTF8String, NULL, &options);
    ZLLog(@"avformat_open_input: %d", result);
    av_dict_free(&options);
    if (result < 0) {
        // avformat_open_input frees the context, but not a custom pb.
        if (error) *error = self.streamError ?: ZLAVError(result, @"FFmpeg cannot open the media.");
        [self closeIO:io];
        [self closeAllIO];
        return NO;
    }
    self.context = context;
    result = avformat_find_stream_info(context, NULL);
    ZLLog(@"avformat_find_stream_info: %d", result);
    if (result < 0) {
        if (error) *error = self.streamError ?: ZLAVError(result, @"FFmpeg cannot read the streams.");
        [self close];
        return NO;
    }
    return YES;
}

- (AVIOContext *)openIO:(NSURL *)url error:(NSError **)error {
    ZLHTTPStream *stream = [[ZLHTTPStream alloc] initWithURL:url headers:self.headers];
    if (self.cancelled || ![stream open:error]) return NULL;
    uint8_t *buffer = av_malloc(ZLIOBufferSize);
    AVIOContext *io = avio_alloc_context(buffer, ZLIOBufferSize, 0, (__bridge void *)stream, ZLReadPacket, NULL,
                                         ZLSeek);
    io->seekable = stream.seekable ? AVIO_SEEKABLE_NORMAL : 0;
    @synchronized (self.streams) {
        [self.streams addObject:stream];
    }
    return io;
}

- (BOOL)ownsIO:(AVIOContext *)io {
    @synchronized (self.streams) {
        for (ZLHTTPStream *stream in self.streams) {
            if ((__bridge void *)stream == io->opaque) return YES;
        }
    }
    return NO;
}

- (void)closeIO:(AVIOContext *)io {
    if (!io) return;
    ZLHTTPStream *stream = (__bridge ZLHTTPStream *)io->opaque;
    [stream close];
    @synchronized (self.streams) {
        [self.streams removeObjectIdenticalTo:stream];
    }
    av_freep(&io->buffer);
    avio_context_free(&io);
}

- (void)closeAllIO {
    @synchronized (self.streams) {
        for (ZLHTTPStream *stream in self.streams) [stream close];
        [self.streams removeAllObjects];
    }
}

- (void)cancel {
    self.cancelled = YES;
    @synchronized (self.streams) {
        for (ZLHTTPStream *stream in self.streams) [stream close];
    }
}

- (void)close {
    AVFormatContext *context = self.context;
    self.context = NULL;
    if (!context) return;
    AVIOContext *pb = (context->flags & AVFMT_FLAG_CUSTOM_IO) ? context->pb : NULL;
    avformat_close_input(&context);
    if (pb) [self closeIO:pb];
    [self closeAllIO];
}

@end
