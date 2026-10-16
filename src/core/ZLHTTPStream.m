#import "ZLHTTPStream.h"
#import "ZLConnection.h"
#import "ZLLog.h"
#include <zlib.h>

// The connection stops when it is this far ahead of the reader.
static const int64_t ZLMaxAhead = 8 * 1024 * 1024;
// A stopped connection starts again when it is this near to the reader.
static const int64_t ZLResumeAhead = 2 * 1024 * 1024;
// A seek forward by less than this waits for the bytes. A longer seek starts
// a new connection.
static const int64_t ZLNearSeek = 512 * 1024;
// The bytes before the read position that the stream keeps for a short seek back.
static const int64_t ZLKeepBehind = 256 * 1024;
// The longest response head that the stream reads.
static const NSUInteger ZLMaxHead = 64 * 1024;
static const int ZLMaxRedirects = 8;

static NSString *const ZLUserAgent = @"Mozilla/5.0 (iPhone; CPU iPhone OS 6_1_3 like Mac OS X) AppleWebKit/536.26 "
                                     @"(KHTML, like Gecko) Version/6.0 Mobile/10B329 Safari/8536.25 ZettaLite";

// The head of a response.
@interface ZLResponseHead : NSObject
@property (nonatomic) NSInteger status;
@property (nonatomic, strong) NSDictionary *headers;  // Names in lower case.
@end

@implementation ZLResponseHead
@end

@interface ZLHTTPStream ()
@property (nonatomic, strong) NSURL *URL;
@property (nonatomic, strong) NSURL *finalURL;
@property (nonatomic, copy) NSDictionary *headers;
@property (nonatomic, strong) ZLTrust *trust;
@property (nonatomic, strong) NSCondition *condition;
@property (nonatomic, strong) ZLConnection *connection;
@property (nonatomic, strong) NSMutableData *buffer;
@property (nonatomic) int64_t bufferStart;
@property (nonatomic) int64_t position;
@property (nonatomic) int64_t length;
@property (nonatomic) BOOL seekable;
@property (nonatomic, copy) NSString *contentType;
@property (nonatomic) BOOL responded;
@property (nonatomic) BOOL finished;
@property (nonatomic) BOOL stopped;  // Stopped because it was far ahead.
@property (nonatomic) BOOL closed;
@property (nonatomic) int64_t skip;  // Bytes to drop when a server ignores the range.
@property (nonatomic) NSUInteger generation;
@property (nonatomic, strong) NSError *error;
@property (nonatomic) int retries;
@end

@implementation ZLHTTPStream

- (instancetype)initWithURL:(NSURL *)url headers:(NSDictionary *)headers {
    return [self initWithURL:url headers:headers trust:[ZLTrust shared]];
}

- (instancetype)initWithURL:(NSURL *)url headers:(NSDictionary *)headers trust:(ZLTrust *)trust {
    if ((self = [super init])) {
        _URL = url;
        _finalURL = url;
        _headers = [headers copy];
        _trust = trust;
        _condition = [NSCondition new];
        _buffer = [NSMutableData data];
        _length = -1;
        _timeout = 30;
    }
    return self;
}

- (void)dealloc {
    [_connection close];
}

#pragma mark - Connection

// Call with the condition locked. A new connection starts at offset. With
// keep, the buffer stays, and offset must be the end of the buffer.
- (void)startAt:(int64_t)offset keep:(BOOL)keep {
    [self.connection close];
    self.connection = nil;
    self.generation++;
    if (!keep) {
        self.buffer = [NSMutableData data];
        self.bufferStart = offset;
    }
    self.finished = NO;
    self.stopped = NO;
    self.error = nil;
    self.skip = 0;
    ZLLog(@"http %@ from %lld", self.URL.lastPathComponent, offset);
    NSDictionary *job = @{ @"offset": @(offset), @"generation": @(self.generation), @"url": self.finalURL };
    [NSThread detachNewThreadSelector:@selector(run:) toTarget:self withObject:job];
}

// Call with the condition locked.
- (BOOL)isCurrent:(NSUInteger)generation {
    return generation == self.generation && !self.closed;
}

static NSString *ZLRequestTarget(NSURL *url) {
    // resourceSpecifier keeps the percent escapes: //host:port/path?query#fragment
    NSString *rest = url.resourceSpecifier;
    if ([rest hasPrefix:@"//"]) {
        NSRange slash = [rest rangeOfString:@"/" options:0 range:NSMakeRange(2, rest.length - 2)];
        NSRange question = [rest rangeOfString:@"?" options:0 range:NSMakeRange(2, rest.length - 2)];
        if (slash.location == NSNotFound && question.location == NSNotFound) {
            rest = @"/";
        } else if (slash.location == NSNotFound || question.location < slash.location) {
            rest = [@"/" stringByAppendingString:[rest substringFromIndex:question.location]];
        } else {
            rest = [rest substringFromIndex:slash.location];
        }
    }
    NSRange hash = [rest rangeOfString:@"#"];
    if (hash.location != NSNotFound) rest = [rest substringToIndex:hash.location];
    return rest.length ? rest : @"/";
}

- (NSData *)requestFor:(NSURL *)url offset:(int64_t)offset {
    BOOL tls = [url.scheme.lowercaseString isEqualToString:@"https"];
    NSString *host = url.host;
    if (url.port && url.port.intValue != (tls ? 443 : 80)) host = [host stringByAppendingFormat:@":%@", url.port];
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    fields[@"Host"] = host;
    fields[@"User-Agent"] = ZLUserAgent;
    fields[@"Accept"] = @"*/*";
    fields[@"Accept-Encoding"] = @"identity";
    fields[@"Connection"] = @"close";
    // Also the first request asks for a range. Many servers accept ranges
    // but do not say so in a 200 answer. With a range, they answer 206.
    fields[@"Range"] = [NSString stringWithFormat:@"bytes=%lld-", offset];
    // The headers of the caller replace the defaults with the same name.
    [self.headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        for (NSString *name in fields.allKeys) {
            if ([name caseInsensitiveCompare:key] == NSOrderedSame) [fields removeObjectForKey:name];
        }
        fields[key] = value;
    }];
    NSMutableString *text = [NSMutableString stringWithFormat:@"GET %@ HTTP/1.1\r\n", ZLRequestTarget(url)];
    [fields enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        [text appendFormat:@"%@: %@\r\n", key, value];
    }];
    [text appendString:@"\r\n"];
    return [text dataUsingEncoding:NSUTF8StringEncoding];
}

// Reads the response head. The bytes after the head go to body.
static ZLResponseHead *ZLReadHead(ZLConnection *connection, NSMutableData *body, NSError **error) {
    NSMutableData *data = [NSMutableData data];
    uint8_t chunk[4096];
    NSRange end = NSMakeRange(NSNotFound, 0);
    NSData *marker = [NSData dataWithBytes:"\r\n\r\n" length:4];
    while (end.location == NSNotFound) {
        if (data.length > ZLMaxHead) {
            if (error) *error = ZLMakeError(ZLErrorMedia, @"The server sent a response head that is too long.");
            return nil;
        }
        NSInteger count = [connection read:chunk length:sizeof(chunk) error:error];
        if (count <= 0) {
            if (count == 0 && error) *error = ZLMakeError(ZLErrorMedia, @"The server closed the connection.");
            return nil;
        }
        [data appendBytes:chunk length:(NSUInteger)count];
        end = [data rangeOfData:marker options:0 range:NSMakeRange(0, data.length)];
    }
    NSUInteger bodyStart = end.location + 4;
    [body appendBytes:(const uint8_t *)data.bytes + bodyStart length:data.length - bodyStart];
    NSString *text = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, end.location)]
                                           encoding:NSISOLatin1StringEncoding];
    NSArray *lines = [text componentsSeparatedByString:@"\r\n"];
    NSArray *words = [lines.firstObject componentsSeparatedByString:@" "];
    ZLResponseHead *head = [ZLResponseHead new];
    head.status = words.count >= 2 ? [words[1] integerValue] : 0;
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    for (NSUInteger i = 1; i < lines.count; i++) {
        NSString *line = lines[i];
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound) continue;
        NSString *name = [[line substringToIndex:colon.location] lowercaseString];
        NSString *value = [[line substringFromIndex:colon.location + 1]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        headers[name] = value;
    }
    head.headers = headers;
    if (head.status < 100) {
        if (error) *error = ZLMakeError(ZLErrorMedia, @"The server sent a response that the app cannot read.");
        return nil;
    }
    return head;
}

static int64_t ZLTotalFromContentRange(NSString *range) {
    NSRange slash = [range rangeOfString:@"/"];
    if (slash.location == NSNotFound) return -1;
    NSString *total = [range substringFromIndex:slash.location + 1];
    return [total isEqualToString:@"*"] ? -1 : total.longLongValue;
}

// The thread of one connection. It connects, follows the redirects, and reads
// the body into the buffer.
- (void)run:(NSDictionary *)job {
    @autoreleasepool {
        NSUInteger generation = [job[@"generation"] unsignedIntegerValue];
        int64_t offset = [job[@"offset"] longLongValue];
        NSURL *url = job[@"url"];
        NSError *error = nil;
        ZLConnection *connection = nil;
        ZLResponseHead *head = nil;
        NSMutableData *pending = [NSMutableData data];
        for (int redirects = 0; redirects <= ZLMaxRedirects; redirects++) {
            BOOL tls = [url.scheme.lowercaseString isEqualToString:@"https"];
            int port = url.port ? url.port.intValue : (tls ? 443 : 80);
            connection = url.host ? [ZLConnection connectToHost:url.host port:port tls:tls trust:self.trust timeout:20 error:&error] : nil;
            if (!connection) {
                if (!error) error = ZLMakeError(ZLErrorMedia, @"The link has no host.");
                break;
            }
            [self.condition lock];
            BOOL current = [self isCurrent:generation];
            if (current) self.connection = connection;
            [self.condition unlock];
            if (!current) {
                [connection close];
                return;
            }
            if (![connection writeData:[self requestFor:url offset:offset] error:&error]) break;
            pending = [NSMutableData data];
            head = ZLReadHead(connection, pending, &error);
            if (!head) break;
            NSString *location = head.headers[@"location"];
            if (head.status >= 300 && head.status < 400 && location.length) {
                [connection close];
                url = [NSURL URLWithString:location relativeToURL:url].absoluteURL;
                head = nil;
                if (!url) {
                    error = ZLMakeError(ZLErrorMedia, @"The server sent a redirect that the app cannot read.");
                    break;
                }
                continue;
            }
            break;
        }
        [self.condition lock];
        BOOL current = [self isCurrent:generation];
        if (current && !head) {
            self.error = error ?: ZLMakeError(ZLErrorMedia, @"The server sent too many redirects.");
            self.connection = nil;
        } else if (current) {
            [self takeHead:head url:url offset:offset];
        }
        [self.condition broadcast];
        [self.condition unlock];
        if (!current || !head || head.status >= 400) {
            [connection close];
            return;
        }
        [self readBodyOf:connection head:head first:pending generation:generation];
    }
}

// Call with the condition locked.
- (void)takeHead:(ZLResponseHead *)head url:(NSURL *)url offset:(int64_t)offset {
    ZLLog(@"http %@ status %ld", self.URL.lastPathComponent, (long)head.status);
    if (head.status >= 400) {
        self.error = ZLMakeError(ZLErrorHTTPStatus, [NSString stringWithFormat:@"The server answered with HTTP %ld.", (long)head.status]);
        self.connection = nil;
        return;
    }
    self.finalURL = url;
    NSString *type = head.headers[@"content-type"];
    NSRange semicolon = [type rangeOfString:@";"];
    self.contentType = semicolon.location == NSNotFound ? type : [type substringToIndex:semicolon.location];
    NSString *encoding = head.headers[@"content-encoding"];
    BOOL encoded = encoding.length && ![encoding.lowercaseString isEqualToString:@"identity"];
    int64_t contentLength = head.headers[@"content-length"] ? [head.headers[@"content-length"] longLongValue] : -1;
    if (head.status == 206) {
        self.seekable = YES;
        int64_t total = ZLTotalFromContentRange(head.headers[@"content-range"]);
        if (total > 0) self.length = total;
    } else {
        // The server sends the full file from the start.
        if (contentLength > 0 && !encoded) self.length = contentLength;
        NSString *ranges = head.headers[@"accept-ranges"];
        self.seekable = [ranges.lowercaseString isEqualToString:@"bytes"] && self.length > 0 && !encoded;
        self.skip = offset;
    }
    self.responded = YES;
}

// Takes the body bytes out of raw. A chunked body loses its chunk lines.
// Returns YES at the end of the body.
static BOOL ZLTakeBody(NSMutableData *raw, NSMutableData *body, BOOL chunked, int64_t *left, int64_t *chunkLeft) {
    if (!chunked) {
        NSUInteger take = *left >= 0 ? (NSUInteger)MIN((int64_t)raw.length, *left) : raw.length;
        [body appendBytes:raw.bytes length:take];
        [raw setLength:0];
        if (*left >= 0) {
            *left -= take;
            return *left == 0;
        }
        return NO;
    }
    NSData *crlf = [NSData dataWithBytes:"\r\n" length:2];
    while (raw.length) {
        if (*chunkLeft > 0) {
            NSUInteger take = (NSUInteger)MIN((int64_t)raw.length, *chunkLeft);
            [body appendBytes:raw.bytes length:take];
            [raw replaceBytesInRange:NSMakeRange(0, take) withBytes:NULL length:0];
            *chunkLeft -= take;
            continue;
        }
        // A chunk ends with CRLF. Then the line with the next size follows.
        NSRange line = [raw rangeOfData:crlf options:0 range:NSMakeRange(0, raw.length)];
        if (line.location == NSNotFound) return NO;
        NSString *size = [[NSString alloc] initWithData:[raw subdataWithRange:NSMakeRange(0, line.location)]
                                               encoding:NSASCIIStringEncoding];
        [raw replaceBytesInRange:NSMakeRange(0, line.location + 2) withBytes:NULL length:0];
        if (size.length == 0) continue;
        unsigned long long value = 0;
        [[NSScanner scannerWithString:size] scanHexLongLong:&value];
        if (value == 0) return YES;
        *chunkLeft = (int64_t)value;
    }
    return NO;
}

// Reads the body, with chunked transfer and gzip, into the buffer.
- (void)readBodyOf:(ZLConnection *)connection head:(ZLResponseHead *)head first:(NSData *)first
        generation:(NSUInteger)generation {
    // A missing header is nil, and a range in nil has location 0. So check it first.
    NSString *transfer = [head.headers[@"transfer-encoding"] lowercaseString];
    BOOL chunked = transfer && [transfer rangeOfString:@"chunked"].location != NSNotFound;
    NSString *encoding = [head.headers[@"content-encoding"] lowercaseString];
    BOOL compressed = [encoding isEqualToString:@"gzip"] || [encoding isEqualToString:@"deflate"];
    int64_t left = (!chunked && head.headers[@"content-length"]) ? [head.headers[@"content-length"] longLongValue] : -1;
    int64_t chunkLeft = 0;
    z_stream zip;
    memset(&zip, 0, sizeof(zip));
    if (compressed) inflateInit2(&zip, 15 + 32);  // 32: a gzip or a zlib header.

    NSMutableData *raw = [first mutableCopy];
    BOOL done = NO;
    NSError *error = nil;
    uint8_t chunk[32768];
    while (YES) {
        NSMutableData *body = [NSMutableData data];
        done = ZLTakeBody(raw, body, chunked, &left, &chunkLeft);
        if (compressed && body.length) {
            NSMutableData *plain = [NSMutableData data];
            zip.next_in = (Bytef *)body.bytes;
            zip.avail_in = (uInt)body.length;
            uint8_t out[32768];
            while (zip.avail_in > 0) {
                zip.next_out = out;
                zip.avail_out = sizeof(out);
                int status = inflate(&zip, Z_NO_FLUSH);
                [plain appendBytes:out length:sizeof(out) - zip.avail_out];
                if (status == Z_STREAM_END) break;
                if (status != Z_OK && status != Z_BUF_ERROR) {
                    error = ZLMakeError(ZLErrorMedia, @"The server sent compressed data that the app cannot read.");
                    break;
                }
            }
            body = plain;
        }
        if (body.length && ![self append:body generation:generation connection:connection]) {
            if (compressed) inflateEnd(&zip);
            return;
        }
        if (done || error) break;
        NSInteger count = [connection read:chunk length:sizeof(chunk) error:&error];
        if (count < 0) break;
        if (count == 0) {
            // A body with no length ends when the server closes.
            done = left < 0 && !chunked;
            if (!done) error = ZLMakeError(ZLErrorMedia, @"The server closed the connection early.");
            break;
        }
        [raw appendBytes:chunk length:(NSUInteger)count];
    }
    if (compressed) inflateEnd(&zip);
    [connection close];
    [self.condition lock];
    if ([self isCurrent:generation] && !self.stopped) {
        self.connection = nil;
        if (!done) {
            self.error = error ?: ZLMakeError(ZLErrorMedia, @"The connection failed.");
        } else {
            self.finished = YES;
            int64_t end = self.bufferStart + (int64_t)self.buffer.length;
            if (self.length < 0 || end > self.length) self.length = end;
        }
        [self.condition broadcast];
    }
    [self.condition unlock];
}

// Puts body bytes into the buffer. Returns NO when the thread must stop.
- (BOOL)append:(NSData *)data generation:(NSUInteger)generation connection:(ZLConnection *)connection {
    [self.condition lock];
    BOOL current = [self isCurrent:generation];
    if (current) {
        NSUInteger offset = 0;
        if (self.skip > 0) {
            offset = (NSUInteger)MIN((int64_t)data.length, self.skip);
            self.skip -= offset;
        }
        if (offset < data.length) {
            [self.buffer appendBytes:(const uint8_t *)data.bytes + offset length:data.length - offset];
            self.retries = 0;
        }
        int64_t end = self.bufferStart + (int64_t)self.buffer.length;
        if (self.seekable && end - _position > ZLMaxAhead) {
            self.connection = nil;
            self.stopped = YES;
            current = NO;
        }
        [self.condition broadcast];
    }
    [self.condition unlock];
    if (!current) [connection close];
    return current;
}

#pragma mark - Reading

- (BOOL)open:(NSError **)error {
    [self.condition lock];
    [self startAt:0 keep:NO];
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:self.timeout];
    while (!self.responded && !self.error && !self.closed) {
        if (![self.condition waitUntilDate:until]) break;
    }
    BOOL ok = self.responded;
    if (!ok && error) *error = self.error ?: ZLMakeError(ZLErrorTimeout, @"The server did not answer.");
    [self.condition unlock];
    return ok;
}

- (NSInteger)read:(uint8_t *)bytes length:(NSUInteger)length error:(NSError **)error {
    [self.condition lock];
    NSInteger result = -1;
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:self.timeout];
    while (YES) {
        if (self.closed) {
            if (error) *error = ZLMakeError(ZLErrorCancelled, @"The stream is closed.");
            break;
        }
        int64_t end = self.bufferStart + (int64_t)self.buffer.length;
        if (_position >= self.bufferStart && _position < end) {
            NSUInteger count = (NSUInteger)MIN((int64_t)length, end - _position);
            memcpy(bytes, (const uint8_t *)self.buffer.bytes + (_position - self.bufferStart), count);
            _position += count;
            [self trim];
            if (self.stopped && end - _position < ZLResumeAhead) [self startAt:end keep:YES];
            result = (NSInteger)count;
            break;
        }
        if (self.length >= 0 && _position >= self.length) {
            result = 0;
            break;
        }
        if (self.finished && _position >= end) {
            result = 0;
            break;
        }
        BOOL far = _position < self.bufferStart || _position > end + ZLNearSeek;
        if (far || self.stopped) {
            if (!self.seekable && _position < self.bufferStart) {
                if (error) *error = ZLMakeError(ZLErrorMedia, @"The server does not accept a seek back.");
                break;
            }
            [self startAt:far ? _position : end keep:!far];
            until = [NSDate dateWithTimeIntervalSinceNow:self.timeout];
            continue;
        }
        if (self.error) {
            BOOL retry = self.seekable && self.retries < 3 && self.error.code != ZLErrorUntrustedHost &&
                         self.error.code != ZLErrorHTTPStatus && self.error.code != ZLErrorCancelled;
            if (!retry) {
                if (error) *error = self.error;
                break;
            }
            self.retries++;
            [self startAt:end keep:YES];
            until = [NSDate dateWithTimeIntervalSinceNow:self.timeout];
            continue;
        }
        if (![self.condition waitUntilDate:until]) {
            if (error) *error = ZLMakeError(ZLErrorTimeout, @"The server stopped sending data.");
            break;
        }
    }
    [self.condition unlock];
    return result;
}

// Call with the condition locked. Removes the bytes far behind the reader.
- (void)trim {
    int64_t drop = _position - ZLKeepBehind - self.bufferStart;
    if (drop > ZLKeepBehind) {
        [self.buffer replaceBytesInRange:NSMakeRange(0, (NSUInteger)drop) withBytes:NULL length:0];
        self.bufferStart += drop;
    }
}

- (BOOL)seekTo:(int64_t)offset error:(NSError **)error {
    [self.condition lock];
    BOOL ok = offset >= 0 && (self.seekable || offset >= self.bufferStart);
    if (ok) _position = offset;
    else if (error) *error = ZLMakeError(ZLErrorMedia, @"The server does not accept a seek.");
    [self.condition unlock];
    return ok;
}

- (int64_t)position {
    [self.condition lock];
    int64_t position = _position;
    [self.condition unlock];
    return position;
}

- (void)close {
    [self.condition lock];
    self.closed = YES;
    [self.connection close];
    self.connection = nil;
    [self.condition broadcast];
    [self.condition unlock];
}

+ (NSData *)fetch:(NSURL *)url headers:(NSDictionary *)headers finalURL:(NSURL **)finalURL error:(NSError **)error {
    ZLHTTPStream *stream = [[ZLHTTPStream alloc] initWithURL:url headers:headers];
    if (![stream open:error]) return nil;
    NSMutableData *data = [NSMutableData data];
    uint8_t chunk[16384];
    while (YES) {
        NSInteger count = [stream read:chunk length:sizeof(chunk) error:error];
        if (count < 0) {
            [stream close];
            return nil;
        }
        if (count == 0) break;
        [data appendBytes:chunk length:(NSUInteger)count];
    }
    [stream close];
    if (finalURL) *finalURL = stream.finalURL;
    return data;
}

@end
