#import "ZLHTTPStream.h"

// The connection stops when it is this far ahead of the reader.
static const int64_t ZLMaxAhead = 8 * 1024 * 1024;
// A stopped connection starts again when it is this near to the reader.
static const int64_t ZLResumeAhead = 2 * 1024 * 1024;
// A seek forward by less than this waits for the bytes. A longer seek starts
// a new connection.
static const int64_t ZLNearSeek = 512 * 1024;
// The bytes before the read position that the stream keeps for a short seek back.
static const int64_t ZLKeepBehind = 256 * 1024;

// All connections run on one thread with a run loop.
static NSThread *ZLNetworkThread(void) {
    static NSThread *thread;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        thread = [[NSThread alloc] initWithTarget:[ZLHTTPStream class] selector:@selector(runNetworkThread) object:nil];
        thread.name = @"ZLHTTPStream";
        [thread start];
    });
    return thread;
}

@interface ZLHTTPStream () <NSURLConnectionDataDelegate>
@property (nonatomic, strong) NSURL *URL;
@property (nonatomic, strong) NSURL *finalURL;
@property (nonatomic, copy) NSDictionary *headers;
@property (nonatomic, strong) ZLTrust *trust;
@property (nonatomic, strong) NSCondition *condition;
@property (nonatomic, strong) NSURLConnection *connection;
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
@property (nonatomic, copy) NSString *untrustedHost;
@property (nonatomic) int retries;
@end

@implementation ZLHTTPStream

+ (void)runNetworkThread {
    @autoreleasepool {
        NSRunLoop *loop = [NSRunLoop currentRunLoop];
        [loop addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
        while (YES) {
            @autoreleasepool {
                [loop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
            }
        }
    }
}

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
    NSURLConnection *connection = _connection;
    if (connection) [connection performSelector:@selector(cancel) onThread:ZLNetworkThread() withObject:nil waitUntilDone:NO];
}

#pragma mark - Connection

// Call with the condition locked. A new connection starts at offset. With
// keep, the buffer stays, and offset must be the end of the buffer.
- (void)startAt:(int64_t)offset keep:(BOOL)keep {
    NSURLConnection *old = self.connection;
    if (old) [old performSelector:@selector(cancel) onThread:ZLNetworkThread() withObject:nil waitUntilDone:NO];
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
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.URL
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:20];
    [self.headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        [request setValue:value forHTTPHeaderField:key];
    }];
    if (offset > 0) [request setValue:[NSString stringWithFormat:@"bytes=%lld-", offset] forHTTPHeaderField:@"Range"];
    NSDictionary *job = @{ @"request": request, @"generation": @(self.generation) };
    [self performSelector:@selector(connectOnNetworkThread:) onThread:ZLNetworkThread() withObject:job waitUntilDone:NO];
}

- (void)connectOnNetworkThread:(NSDictionary *)job {
    [self.condition lock];
    BOOL current = [job[@"generation"] unsignedIntegerValue] == self.generation && !self.closed;
    [self.condition unlock];
    if (!current) return;
    NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:job[@"request"] delegate:self startImmediately:NO];
    [connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.condition lock];
    self.connection = connection;
    [self.condition unlock];
    [connection start];
}

// The delegate methods run on the network thread. Each one ignores a
// connection that is not the current one.
- (BOOL)isCurrent:(NSURLConnection *)connection {
    return connection == self.connection && !self.closed;
}

- (void)connection:(NSURLConnection *)connection
    willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    NSURLProtectionSpace *space = challenge.protectionSpace;
    // The 9.3 SDK puts NSURLAuthenticationMethodServerTrust in CFNetwork, and
    // iOS 6 has it in Foundation. Its value is its name, so use the text.
    if (![space.authenticationMethod isEqualToString:@"NSURLAuthenticationMethodServerTrust"]) {
        [challenge.sender performDefaultHandlingForAuthenticationChallenge:challenge];
        return;
    }
    if ([self.trust acceptTrust:space.serverTrust host:space.host]) {
        [challenge.sender useCredential:[NSURLCredential credentialForTrust:space.serverTrust] forAuthenticationChallenge:challenge];
    } else {
        [self.condition lock];
        self.untrustedHost = space.host;
        [self.condition unlock];
        [challenge.sender cancelAuthenticationChallenge:challenge];
    }
}

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request
            redirectResponse:(NSURLResponse *)response {
    if (!response) return request;
    // A redirect loses the headers of the first request. Add them again.
    NSMutableURLRequest *next = [request mutableCopy];
    [self.condition lock];
    NSDictionary *headers = self.headers;
    [self.condition unlock];
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        if (![next valueForHTTPHeaderField:key]) [next setValue:value forHTTPHeaderField:key];
    }];
    return next;
}

static int64_t ZLTotalFromContentRange(NSString *range) {
    NSRange slash = [range rangeOfString:@"/"];
    if (slash.location == NSNotFound) return -1;
    NSString *total = [range substringFromIndex:slash.location + 1];
    return [total isEqualToString:@"*"] ? -1 : total.longLongValue;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    [self.condition lock];
    if ([self isCurrent:connection]) {
        NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
        NSInteger status = http ? http.statusCode : 200;
        int64_t asked = self.bufferStart + (int64_t)self.buffer.length;
        if (status >= 400) {
            self.error = ZLMakeError(ZLErrorHTTPStatus, [NSString stringWithFormat:@"The server answered with HTTP %ld.", (long)status]);
            [connection cancel];
            self.connection = nil;
        } else {
            self.finalURL = response.URL ?: self.URL;
            self.contentType = response.MIMEType;
            if (status == 206) {
                self.seekable = YES;
                int64_t total = ZLTotalFromContentRange(http.allHeaderFields[@"Content-Range"]);
                if (total > 0) self.length = total;
            } else {
                // The server sends the full file from the start.
                if (response.expectedContentLength > 0) self.length = response.expectedContentLength;
                NSString *ranges = http.allHeaderFields[@"Accept-Ranges"];
                self.seekable = [ranges.lowercaseString isEqualToString:@"bytes"] && self.length > 0;
                self.skip = asked;
            }
            self.responded = YES;
        }
        [self.condition broadcast];
    }
    [self.condition unlock];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.condition lock];
    if ([self isCurrent:connection]) {
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
            [connection cancel];
            self.connection = nil;
            self.stopped = YES;
        }
        [self.condition broadcast];
    }
    [self.condition unlock];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    [self.condition lock];
    if ([self isCurrent:connection]) {
        self.finished = YES;
        self.connection = nil;
        int64_t end = self.bufferStart + (int64_t)self.buffer.length;
        if (self.length < 0 || end > self.length) self.length = end;
        [self.condition broadcast];
    }
    [self.condition unlock];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [self.condition lock];
    if ([self isCurrent:connection]) {
        self.connection = nil;
        if (self.untrustedHost) {
            NSString *text = [NSString stringWithFormat:@"iOS 6 does not trust the certificate of %@.", self.untrustedHost];
            self.error = [NSError errorWithDomain:ZLErrorDomain code:ZLErrorUntrustedHost
                                         userInfo:@{ NSLocalizedDescriptionKey: text, ZLUntrustedHostKey: self.untrustedHost }];
        } else {
            self.error = error;
        }
        [self.condition broadcast];
    }
    [self.condition unlock];
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
            if (self.seekable || far) {
                [self startAt:far ? _position : end keep:!far];
                until = [NSDate dateWithTimeIntervalSinceNow:self.timeout];
                continue;
            }
        }
        if (self.error) {
            BOOL retry = self.seekable && self.retries < 3 && self.error.code != ZLErrorUntrustedHost &&
                         ![self.error.domain isEqualToString:ZLErrorDomain];
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
    NSURLConnection *connection = self.connection;
    self.connection = nil;
    if (connection) [connection performSelector:@selector(cancel) onThread:ZLNetworkThread() withObject:nil waitUntilDone:NO];
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
