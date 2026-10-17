#import "ZLHTTPStream.h"
#import "ZLConnection.h"
#import "ZLLog.h"
#include <zlib.h>

// The connection waits when it is this far ahead of the reader. Then TCP
// stops the server until the reader comes near again.
static const int64_t ZLMaxAhead = 8 * 1024 * 1024;
static const int64_t ZLResumeAhead = 6 * 1024 * 1024;
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
@property (nonatomic, copy) NSString *version;  // For example "HTTP/1.1".
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
@property (nonatomic) BOOL acceptsRanges;
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
    head.version = words.firstObject;
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
        self.acceptsRanges = YES;
        int64_t total = ZLTotalFromContentRange(head.headers[@"content-range"]);
        if (total > 0) self.length = total;
    } else {
        // The server sends the full file from the start. The stream drops
        // the bytes before the offset.
        if (contentLength > 0 && !encoded) self.length = contentLength;
        self.acceptsRanges = NO;
        self.skip = offset;
    }
    // A file with a length can always seek. Without ranges, a seek starts
    // again from the start of the file and drops the bytes before it.
    self.seekable = self.acceptsRanges || self.length > 0;
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
    if ([self isCurrent:generation]) {
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
        [self.condition broadcast];
        // Wait while the buffer is far ahead of the reader. A seek or a close
        // makes this connection old, and then it stops.
        while ([self isCurrent:generation] &&
               self.bufferStart + (int64_t)self.buffer.length - _position > ZLMaxAhead) {
            [self.condition wait];
            if (self.bufferStart + (int64_t)self.buffer.length - _position < ZLResumeAhead) break;
        }
        current = [self isCurrent:generation];
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
            [self.condition broadcast];
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
        if (far) {
            if (!self.seekable && _position < self.bufferStart) {
                if (error) *error = ZLMakeError(ZLErrorMedia, @"The server does not accept a seek back.");
                break;
            }
            [self startAt:_position keep:NO];
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

// YES for an error that can go away on a second try, for example a TLS read
// that fails while the Wi-Fi of the phone wakes up.
static BOOL ZLCanRetry(NSError *error) {
    if (![error.domain isEqualToString:ZLErrorDomain]) return error != nil;
    return error.code != ZLErrorUntrustedHost && error.code != ZLErrorHTTPStatus && error.code != ZLErrorCancelled;
}

#pragma mark - Small fetches

// A small fetch keeps its connection open for the next fetch to the same
// host. On the A5 chip a new TLS connection costs about half a second.
static const NSTimeInterval ZLIdleLifetime = 15;
static const NSUInteger ZLMaxIdlePerHost = 4;
// The longest body that a small fetch reads.
static const NSUInteger ZLMaxFetch = 32 * 1024 * 1024;

static NSMutableDictionary *ZLIdleTable(void) {
    static NSMutableDictionary *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ table = [NSMutableDictionary dictionary]; });
    return table;
}

static NSString *ZLHostKey(NSURL *url) {
    BOOL tls = [url.scheme.lowercaseString isEqualToString:@"https"];
    int port = url.port ? url.port.intValue : (tls ? 443 : 80);
    return [NSString stringWithFormat:@"%@://%@:%d", tls ? @"https" : @"http", url.host.lowercaseString, port];
}

// Takes the newest idle connection to the host, or returns nil.
static ZLConnection *ZLTakeIdle(NSString *key) {
    NSMutableDictionary *table = ZLIdleTable();
    @synchronized (table) {
        NSMutableArray *list = table[key];
        while (list.count) {
            NSArray *entry = list.lastObject;
            [list removeLastObject];
            if (-[entry[1] timeIntervalSinceNow] < ZLIdleLifetime) return entry[0];
            [entry[0] close];
        }
        return nil;
    }
}

static void ZLKeepIdle(NSString *key, ZLConnection *connection) {
    NSMutableDictionary *table = ZLIdleTable();
    @synchronized (table) {
        NSMutableArray *list = table[key] ?: [NSMutableArray array];
        table[key] = list;
        [list addObject:@[ connection, [NSDate date] ]];
        while (list.count > ZLMaxIdlePerHost) {
            [list[0][0] close];
            [list removeObjectAtIndex:0];
        }
    }
}

static NSData *ZLFetchRequest(NSURL *url, NSDictionary *headers) {
    BOOL tls = [url.scheme.lowercaseString isEqualToString:@"https"];
    NSString *host = url.host;
    if (url.port && url.port.intValue != (tls ? 443 : 80)) host = [host stringByAppendingFormat:@":%@", url.port];
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    fields[@"Host"] = host;
    fields[@"User-Agent"] = ZLUserAgent;
    fields[@"Accept"] = @"*/*";
    // JSON and playlists are text, and gzip makes them several times smaller.
    fields[@"Accept-Encoding"] = @"gzip";
    fields[@"Connection"] = @"keep-alive";
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
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

// Reads a full body: with a length, chunked, or up to the close. Inflates
// gzip. Sets reusable to YES when the connection can carry a next request.
static NSData *ZLReadBody(ZLConnection *connection, ZLResponseHead *head, NSData *first, BOOL *reusable, NSError **error) {
    *reusable = NO;
    NSString *transfer = [head.headers[@"transfer-encoding"] lowercaseString];
    BOOL chunked = transfer && [transfer rangeOfString:@"chunked"].location != NSNotFound;
    NSString *encoding = [head.headers[@"content-encoding"] lowercaseString];
    BOOL compressed = [encoding isEqualToString:@"gzip"] || [encoding isEqualToString:@"deflate"];
    int64_t left = (!chunked && head.headers[@"content-length"]) ? [head.headers[@"content-length"] longLongValue] : -1;
    int64_t chunkLeft = 0;
    NSMutableData *raw = [first mutableCopy];
    NSMutableData *body = [NSMutableData data];
    BOOL done = (!chunked && left == 0) || head.status == 204 || head.status == 304;
    uint8_t chunk[32768];
    while (!done) {
        done = ZLTakeBody(raw, body, chunked, &left, &chunkLeft);
        if (done) break;
        if (body.length > ZLMaxFetch) {
            if (error) *error = ZLMakeError(ZLErrorMedia, @"The answer is too large.");
            return nil;
        }
        NSInteger count = [connection read:chunk length:sizeof(chunk) error:error];
        if (count < 0) return nil;
        if (count == 0) {
            // A body with no length ends when the server closes.
            if (left < 0 && !chunked) break;
            if (error) *error = ZLMakeError(ZLErrorMedia, @"The server closed the connection early.");
            return nil;
        }
        [raw appendBytes:chunk length:(NSUInteger)count];
    }
    NSString *connectionHeader = [head.headers[@"connection"] lowercaseString];
    BOOL closes = [connectionHeader isEqualToString:@"close"] ||
                  ([head.version isEqualToString:@"HTTP/1.0"] && ![connectionHeader isEqualToString:@"keep-alive"]);
    // Bytes after the body mean a server that the app does not understand.
    *reusable = done && !closes && (chunked || left >= 0) && raw.length == 0;
    if (!compressed) return body;
    z_stream zip;
    memset(&zip, 0, sizeof(zip));
    inflateInit2(&zip, 15 + 32);  // 32: a gzip or a zlib header.
    NSMutableData *plain = [NSMutableData dataWithCapacity:body.length * 4];
    zip.next_in = (Bytef *)body.bytes;
    zip.avail_in = (uInt)body.length;
    uint8_t out[32768];
    int status = Z_OK;
    while (zip.avail_in > 0 && status != Z_STREAM_END) {
        zip.next_out = out;
        zip.avail_out = sizeof(out);
        status = inflate(&zip, Z_NO_FLUSH);
        [plain appendBytes:out length:sizeof(out) - zip.avail_out];
        if (status != Z_OK && status != Z_STREAM_END && status != Z_BUF_ERROR) break;
        if (status == Z_BUF_ERROR && zip.avail_out != 0) break;
    }
    inflateEnd(&zip);
    if (status != Z_STREAM_END && status != Z_OK) {
        if (error) *error = ZLMakeError(ZLErrorMedia, @"The server sent compressed data that the app cannot read.");
        return nil;
    }
    return plain;
}

+ (NSData *)fetchOnce:(NSURL *)url headers:(NSDictionary *)headers finalURL:(NSURL **)finalURL error:(NSError **)error {
    for (int redirects = 0; redirects <= ZLMaxRedirects; redirects++) {
        if (!url.host) {
            if (error) *error = ZLMakeError(ZLErrorMedia, @"The link has no host.");
            return nil;
        }
        NSString *key = ZLHostKey(url);
        ZLConnection *connection = ZLTakeIdle(key);
        BOOL reused = connection != nil;
        NSData *request = ZLFetchRequest(url, headers);
        NSMutableData *first = [NSMutableData data];
        ZLResponseHead *head = nil;
        // An idle connection can be closed by the server already. Then the
        // fetch tries one time more with a new connection.
        for (int attempt = 0; attempt < 2 && !head; attempt++) {
            if (!connection) {
                BOOL tls = [url.scheme.lowercaseString isEqualToString:@"https"];
                int port = url.port ? url.port.intValue : (tls ? 443 : 80);
                connection = [ZLConnection connectToHost:url.host port:port tls:tls trust:[ZLTrust shared] timeout:20 error:error];
                if (!connection) return nil;
                reused = NO;
            }
            [first setLength:0];
            if ([connection writeData:request error:error]) head = ZLReadHead(connection, first, error);
            if (!head) {
                [connection close];
                connection = nil;
                if (!reused) return nil;
            }
        }
        if (!head) return nil;
        ZLLog(@"fetch %@ status %ld%@", url.lastPathComponent, (long)head.status, reused ? @", same connection" : @"");
        NSString *location = head.headers[@"location"];
        if (head.status >= 300 && head.status < 400 && location.length) {
            [connection close];
            url = [NSURL URLWithString:location relativeToURL:url].absoluteURL;
            if (!url) {
                if (error) *error = ZLMakeError(ZLErrorMedia, @"The server sent a redirect that the app cannot read.");
                return nil;
            }
            continue;
        }
        if (head.status >= 400) {
            [connection close];
            if (error) *error = ZLMakeError(ZLErrorHTTPStatus, [NSString stringWithFormat:@"The server answered with HTTP %ld.", (long)head.status]);
            return nil;
        }
        BOOL reusable = NO;
        NSData *body = ZLReadBody(connection, head, first, &reusable, error);
        if (body && reusable) ZLKeepIdle(key, connection);
        else [connection close];
        if (!body) return nil;
        if (finalURL) *finalURL = url;
        return body;
    }
    if (error) *error = ZLMakeError(ZLErrorMedia, @"The server sent too many redirects.");
    return nil;
}

+ (NSData *)fetch:(NSURL *)url headers:(NSDictionary *)headers finalURL:(NSURL **)finalURL error:(NSError **)error {
    NSError *failure = nil;
    NSData *data = [self fetchOnce:url headers:headers finalURL:finalURL error:&failure];
    if (!data && ZLCanRetry(failure)) {
        [NSThread sleepForTimeInterval:0.5];
        failure = nil;
        data = [self fetchOnce:url headers:headers finalURL:finalURL error:&failure];
    }
    if (!data && error) *error = failure;
    return data;
}

@end
