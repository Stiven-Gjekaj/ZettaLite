#import "ZLHLSServer.h"
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

// The longest request head that the server reads.
static const size_t ZLMaxRequestHead = 8192;

@interface ZLHLSServer ()
@property (nonatomic) uint16_t port;
@property (nonatomic) int listenSocket;
@property (nonatomic, strong) dispatch_source_t acceptSource;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) NSMutableDictionary *sources;
@property (nonatomic) NSUInteger nextId;
@end

@implementation ZLHLSServer

+ (instancetype)shared {
    static ZLHLSServer *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [ZLHLSServer new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _listenSocket = -1;
        _sources = [NSMutableDictionary dictionary];
        _queue = dispatch_queue_create("ZLHLSServer.accept", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (BOOL)start:(NSError **)error {
    if (self.listenSocket >= 0) return YES;
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        return NO;
    }
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;  // The system picks a free port.
    socklen_t length = sizeof(address);
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(fd, 16) != 0 ||
        getsockname(fd, (struct sockaddr *)&address, &length) != 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        close(fd);
        return NO;
    }
    self.listenSocket = fd;
    self.port = ntohs(address.sin_port);
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, self.queue);
    __weak ZLHLSServer *weakSelf = self;
    dispatch_source_set_event_handler(source, ^{
        int client = accept(fd, NULL, NULL);
        if (client < 0) return;
        int on = 1;
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof(on));
        // Each connection gets its own thread from the global queue, because
        // a segment can wait for the network.
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            [weakSelf serve:client];
        });
    });
    dispatch_source_set_cancel_handler(source, ^{ close(fd); });
    self.acceptSource = source;
    dispatch_resume(source);
    return YES;
}

- (void)stop {
    if (self.acceptSource) dispatch_source_cancel(self.acceptSource);
    self.acceptSource = nil;
    self.listenSocket = -1;
}

- (NSURL *)addSource:(id<ZLHLSSource>)source {
    NSString *key;
    @synchronized (self.sources) {
        key = [NSString stringWithFormat:@"s%lu", (unsigned long)++self.nextId];
        self.sources[key] = source;
    }
    return [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%u/%@/index.m3u8", self.port, key]];
}

- (void)removeSource:(id<ZLHLSSource>)source {
    @synchronized (self.sources) {
        for (NSString *key in [self.sources allKeysForObject:source]) [self.sources removeObjectForKey:key];
    }
}

static BOOL ZLWriteAll(int fd, const void *bytes, size_t length) {
    const uint8_t *p = bytes;
    while (length > 0) {
        ssize_t n = write(fd, p, length);
        if (n <= 0) return NO;
        p += n;
        length -= (size_t)n;
    }
    return YES;
}

static void ZLRespond(int fd, int status, NSString *reason, NSString *type, NSData *body, BOOL headOnly) {
    NSString *head = [NSString stringWithFormat:@"HTTP/1.1 %d %@\r\nContent-Type: %@\r\nContent-Length: %lu\r\n"
                                                @"Cache-Control: no-cache\r\nConnection: close\r\n\r\n",
                                                status, reason, type, (unsigned long)body.length];
    NSData *headData = [head dataUsingEncoding:NSASCIIStringEncoding];
    if (ZLWriteAll(fd, headData.bytes, headData.length) && !headOnly) ZLWriteAll(fd, body.bytes, body.length);
}

- (void)serve:(int)fd {
    @autoreleasepool {
        NSMutableData *request = [NSMutableData data];
        uint8_t buffer[1024];
        while (request.length < ZLMaxRequestHead) {
            ssize_t n = read(fd, buffer, sizeof(buffer));
            if (n <= 0) break;
            [request appendBytes:buffer length:(size_t)n];
            if ([request rangeOfData:[NSData dataWithBytes:"\r\n\r\n" length:4] options:0
                               range:NSMakeRange(0, request.length)].location != NSNotFound) break;
        }
        NSString *text = [[NSString alloc] initWithData:request encoding:NSASCIIStringEncoding];
        NSArray *words = [[[text componentsSeparatedByString:@"\r\n"] firstObject] componentsSeparatedByString:@" "];
        NSString *method = words.count >= 2 ? words[0] : nil;
        NSString *path = words.count >= 2 ? words[1] : nil;
        BOOL head = [method isEqualToString:@"HEAD"];
        if (!head && ![method isEqualToString:@"GET"]) {
            ZLRespond(fd, 405, @"Method Not Allowed", @"text/plain", nil, NO);
            close(fd);
            return;
        }
        NSArray *parts = [path componentsSeparatedByString:@"/"];  // "", session, file
        id<ZLHLSSource> source = nil;
        if (parts.count == 3) {
            @synchronized (self.sources) {
                source = self.sources[parts[1]];
            }
        }
        NSString *file = parts.count == 3 ? parts[2] : nil;
        if (!source) {
            ZLRespond(fd, 404, @"Not Found", @"text/plain", nil, head);
        } else if ([file isEqualToString:@"index.m3u8"]) {
            ZLRespond(fd, 200, @"OK", @"application/vnd.apple.mpegurl", [source playlist], head);
        } else if ([file hasSuffix:@".ts"]) {
            NSString *number = [file stringByDeletingPathExtension];
            NSInteger index = number.integerValue;
            NSData *segment = nil;
            if ([[NSString stringWithFormat:@"%ld", (long)index] isEqualToString:number] && index >= 0) {
                segment = [source segmentAtIndex:(NSUInteger)index error:NULL];
            }
            if (segment) ZLRespond(fd, 200, @"OK", @"video/mp2t", segment, head);
            else ZLRespond(fd, 502, @"Bad Gateway", @"text/plain", nil, head);
        } else {
            ZLRespond(fd, 404, @"Not Found", @"text/plain", nil, head);
        }
        close(fd);
    }
}

@end
