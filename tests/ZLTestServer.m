#import "ZLTestServer.h"
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

NSData *ZLTestPattern(NSUInteger length) {
    NSMutableData *data = [NSMutableData dataWithLength:length];
    uint8_t *bytes = data.mutableBytes;
    for (NSUInteger i = 0; i < length; i++) bytes[i] = (uint8_t)((i * 7 + i / 251) & 0xff);
    return data;
}

@interface ZLTestServer ()
@property (nonatomic) uint16_t port;
@property (nonatomic) int listenSocket;
@property (nonatomic, strong) NSMutableDictionary *routes;
@property (nonatomic, strong) NSDictionary *lastHeaders;
@property (nonatomic) NSUInteger requestCount;
@end

@implementation ZLTestServer

- (instancetype)init {
    if ((self = [super init])) {
        _listenSocket = -1;
        _routes = [NSMutableDictionary dictionary];
        _acceptsRanges = YES;
        _chunkSize = 65536;
    }
    return self;
}

- (BOOL)start {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    socklen_t length = sizeof(address);
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(fd, 16) != 0 ||
        getsockname(fd, (struct sockaddr *)&address, &length) != 0) {
        close(fd);
        return NO;
    }
    self.listenSocket = fd;
    self.port = ntohs(address.sin_port);
    [NSThread detachNewThreadSelector:@selector(acceptLoop) toTarget:self withObject:nil];
    return YES;
}

- (void)stop {
    int fd = self.listenSocket;
    self.listenSocket = -1;
    if (fd >= 0) {
        shutdown(fd, SHUT_RDWR);
        close(fd);
    }
}

- (NSURL *)serve:(NSData *)body at:(NSString *)path type:(NSString *)type {
    @synchronized (self.routes) {
        self.routes[path] = @{ @"body": body, @"type": type ?: @"application/octet-stream" };
    }
    return [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%u%@", self.port, path]];
}

- (NSURL *)redirect:(NSString *)path to:(NSString *)target {
    @synchronized (self.routes) {
        self.routes[path] = @{ @"redirect": target };
    }
    return [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%u%@", self.port, path]];
}

- (void)acceptLoop {
    while (self.listenSocket >= 0) {
        int client = accept(self.listenSocket, NULL, NULL);
        if (client < 0) break;
        int on = 1;
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof(on));
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ [self serve:client]; });
    }
}

static BOOL WriteAll(int fd, const uint8_t *bytes, size_t length, size_t chunk) {
    while (length > 0) {
        ssize_t n = write(fd, bytes, MIN(length, chunk));
        if (n <= 0) return NO;
        bytes += n;
        length -= (size_t)n;
    }
    return YES;
}

- (void)serve:(int)fd {
    @autoreleasepool {
        NSMutableData *request = [NSMutableData data];
        uint8_t buffer[4096];
        while (request.length < 16384) {
            ssize_t n = read(fd, buffer, sizeof(buffer));
            if (n <= 0) break;
            [request appendBytes:buffer length:(size_t)n];
            if (strnstr(request.bytes, "\r\n\r\n", request.length)) break;
        }
        NSString *text = [[NSString alloc] initWithData:request encoding:NSISOLatin1StringEncoding];
        NSArray *lines = [text componentsSeparatedByString:@"\r\n"];
        NSArray *words = [lines.firstObject componentsSeparatedByString:@" "];
        NSString *path = words.count > 1 ? words[1] : @"";
        NSMutableDictionary *headers = [NSMutableDictionary dictionary];
        for (NSString *line in lines) {
            NSRange colon = [line rangeOfString:@":"];
            if (colon.location == NSNotFound) continue;
            NSString *name = [[line substringToIndex:colon.location] lowercaseString];
            headers[name] = [[line substringFromIndex:colon.location + 1]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }
        NSDictionary *route;
        @synchronized (self.routes) {
            self.lastHeaders = headers;
            self.requestCount++;
            route = self.routes[path];
        }
        NSString *head;
        NSData *body = nil;
        NSUInteger start = 0, end = 0;
        if (route[@"redirect"]) {
            head = [NSString stringWithFormat:@"HTTP/1.1 302 Found\r\nLocation: %@\r\nContent-Length: 0\r\n", route[@"redirect"]];
        } else if (!route) {
            head = @"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n";
        } else {
            body = route[@"body"];
            end = body.length;
            NSString *range = headers[@"range"];
            if (self.acceptsRanges && [range hasPrefix:@"bytes="]) {
                NSArray *parts = [[range substringFromIndex:6] componentsSeparatedByString:@"-"];
                start = (NSUInteger)[parts[0] longLongValue];
                if (parts.count > 1 && [parts[1] length]) end = MIN(body.length, (NSUInteger)[parts[1] longLongValue] + 1);
                head = [NSString stringWithFormat:@"HTTP/1.1 206 Partial Content\r\nContent-Type: %@\r\nAccept-Ranges: bytes\r\n"
                                                  @"Content-Range: bytes %lu-%lu/%lu\r\nContent-Length: %lu\r\n",
                                                  route[@"type"], (unsigned long)start, (unsigned long)end - 1,
                                                  (unsigned long)body.length, (unsigned long)(end - start)];
            } else if (self.chunked) {
                head = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: %@\r\nTransfer-Encoding: chunked\r\n",
                                                  route[@"type"]];
                // Chunks of 1000 bytes, then the last chunk of size 0.
                NSMutableData *chunks = [NSMutableData data];
                for (NSUInteger at = 0; at < body.length; at += 1000) {
                    NSUInteger size = MIN(1000u, body.length - at);
                    [chunks appendData:[[NSString stringWithFormat:@"%lx\r\n", (unsigned long)size] dataUsingEncoding:NSASCIIStringEncoding]];
                    [chunks appendData:[body subdataWithRange:NSMakeRange(at, size)]];
                    [chunks appendBytes:"\r\n" length:2];
                }
                [chunks appendBytes:"0\r\n\r\n" length:5];
                body = chunks;
                end = body.length;
            } else {
                head = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: %@\r\n%@Content-Length: %lu\r\n",
                                                  route[@"type"], self.acceptsRanges ? @"Accept-Ranges: bytes\r\n" : @"",
                                                  (unsigned long)body.length];
            }
        }
        head = [head stringByAppendingString:@"Connection: close\r\n\r\n"];
        NSData *headData = [head dataUsingEncoding:NSASCIIStringEncoding];
        if (WriteAll(fd, headData.bytes, headData.length, headData.length) && body) {
            WriteAll(fd, (const uint8_t *)body.bytes + start, end - start, self.chunkSize);
        }
        close(fd);
    }
}

@end
