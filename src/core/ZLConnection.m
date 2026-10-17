#define MBEDTLS_USER_CONFIG_FILE "zl_mbedtls_config.h"
#import "ZLConnection.h"
#import "ZLLog.h"
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <unistd.h>
#include "mbedtls/ctr_drbg.h"
#include "mbedtls/entropy.h"
#include "mbedtls/error.h"
#include "mbedtls/net_sockets.h"
#include "mbedtls/ssl.h"
#include "mbedtls/x509_crt.h"
#include "psa/crypto.h"

static NSString *ZLCertificatePath;

void ZLSetCertificateFile(NSString *path) {
    ZLCertificatePath = [path copy];
}

// The root certificates and the random generator. All connections share them.
static mbedtls_x509_crt ZLRoots;
static mbedtls_entropy_context ZLEntropy;
static mbedtls_ctr_drbg_context ZLRandom;
static BOOL ZLTLSReady;

static BOOL ZLSetUpTLS(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // mbedTLS 3.6 needs PSA crypto for some of its parts.
        if (psa_crypto_init() != PSA_SUCCESS) return;
        mbedtls_x509_crt_init(&ZLRoots);
        mbedtls_entropy_init(&ZLEntropy);
        mbedtls_ctr_drbg_init(&ZLRandom);
        const char *label = "ZettaLite";
        if (mbedtls_ctr_drbg_seed(&ZLRandom, mbedtls_entropy_func, &ZLEntropy, (const unsigned char *)label, strlen(label)) != 0) return;
        NSString *path = ZLCertificatePath ?: [[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"];
        if (!path || mbedtls_x509_crt_parse_file(&ZLRoots, path.fileSystemRepresentation) < 0) return;
        ZLTLSReady = YES;
    });
    return ZLTLSReady;
}

// The last TLS session of each host. A new connection to the host resumes
// it, and so skips the costly part of the handshake: the A5 chip needs about
// half a second for a full handshake.
static NSMutableDictionary *ZLSessions;  // "host:port" -> NSValue with a mbedtls_ssl_session pointer

static NSMutableDictionary *ZLSessionTable(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ ZLSessions = [NSMutableDictionary dictionary]; });
    return ZLSessions;
}

static NSError *ZLTLSError(int code, NSString *text) {
    char reason[160] = {0};
    mbedtls_strerror(code, reason, sizeof(reason));
    return ZLMakeError(ZLErrorMedia, [NSString stringWithFormat:@"%@ (%s)", text, reason]);
}

@interface ZLConnection () {
    mbedtls_ssl_context _ssl;
    mbedtls_ssl_config _config;
}
@property (nonatomic) int socket;
@property (nonatomic) BOOL tls;
@property (atomic) BOOL closed;
@end

static int ZLSend(void *context, const unsigned char *bytes, size_t length) {
    int fd = *(int *)context;
    ssize_t n = send(fd, bytes, length, 0);
    if (n >= 0) return (int)n;
    return (errno == EAGAIN || errno == EINTR) ? MBEDTLS_ERR_SSL_WANT_WRITE : MBEDTLS_ERR_NET_SEND_FAILED;
}

static int ZLReceive(void *context, unsigned char *bytes, size_t length) {
    int fd = *(int *)context;
    ssize_t n = recv(fd, bytes, length, 0);
    if (n >= 0) return (int)n;
    if (errno == EAGAIN || errno == EWOULDBLOCK) return MBEDTLS_ERR_SSL_TIMEOUT;
    return errno == EINTR ? MBEDTLS_ERR_SSL_WANT_READ : MBEDTLS_ERR_NET_RECV_FAILED;
}

// Connects with a time limit. Returns the socket, or -1.
static int ZLConnectSocket(NSString *host, int port, NSTimeInterval timeout, NSError **error) {
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    struct addrinfo *addresses = NULL;
    char service[16];
    snprintf(service, sizeof(service), "%d", port);
    int result = getaddrinfo(host.UTF8String, service, &hints, &addresses);
    if (result != 0 || !addresses) {
        if (error) *error = ZLMakeError(ZLErrorMedia, [NSString stringWithFormat:@"The app cannot find the host %@.", host]);
        return -1;
    }
    int fd = -1;
    for (struct addrinfo *address = addresses; address; address = address->ai_next) {
        fd = socket(address->ai_family, address->ai_socktype, address->ai_protocol);
        if (fd < 0) continue;
        int on = 1;
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof(on));
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &on, sizeof(on));
        int flags = fcntl(fd, F_GETFL, 0);
        fcntl(fd, F_SETFL, flags | O_NONBLOCK);
        int connected = connect(fd, address->ai_addr, address->ai_addrlen);
        if (connected != 0 && errno == EINPROGRESS) {
            fd_set writable;
            FD_ZERO(&writable);
            FD_SET(fd, &writable);
            struct timeval limit = {(long)timeout, 0};
            if (select(fd + 1, NULL, &writable, NULL, &limit) == 1) {
                int failure = 0;
                socklen_t size = sizeof(failure);
                getsockopt(fd, SOL_SOCKET, SO_ERROR, &failure, &size);
                connected = failure == 0 ? 0 : -1;
            }
        }
        if (connected == 0) {
            fcntl(fd, F_SETFL, flags);
            struct timeval limit = {(long)timeout, 0};
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &limit, sizeof(limit));
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &limit, sizeof(limit));
            break;
        }
        close(fd);
        fd = -1;
    }
    freeaddrinfo(addresses);
    if (fd < 0 && error) *error = ZLMakeError(ZLErrorMedia, [NSString stringWithFormat:@"The app cannot connect to %@.", host]);
    return fd;
}

@implementation ZLConnection

+ (instancetype)connectToHost:(NSString *)host port:(int)port tls:(BOOL)tls trust:(ZLTrust *)trust
                      timeout:(NSTimeInterval)timeout error:(NSError **)error {
    if (tls && !ZLSetUpTLS()) {
        if (error) *error = ZLMakeError(ZLErrorMedia, @"The app cannot read its root certificates.");
        return nil;
    }
    int fd = ZLConnectSocket(host, port, timeout, error);
    if (fd < 0) return nil;
    ZLConnection *connection = [ZLConnection new];
    connection.socket = fd;
    connection.tls = tls;
    if (tls && ![connection handshakeWith:host port:port trust:trust error:error]) {
        [connection close];
        return nil;
    }
    return connection;
}

- (BOOL)handshakeWith:(NSString *)host port:(int)port trust:(ZLTrust *)trust error:(NSError **)error {
    mbedtls_ssl_init(&_ssl);
    mbedtls_ssl_config_init(&_config);
    mbedtls_ssl_config_defaults(&_config, MBEDTLS_SSL_IS_CLIENT, MBEDTLS_SSL_TRANSPORT_STREAM, MBEDTLS_SSL_PRESET_DEFAULT);
    // The app checks the result itself, so that it can ask the user.
    mbedtls_ssl_conf_authmode(&_config, MBEDTLS_SSL_VERIFY_OPTIONAL);
    mbedtls_ssl_conf_ca_chain(&_config, &ZLRoots, NULL);
    mbedtls_ssl_conf_rng(&_config, mbedtls_ctr_drbg_random, &ZLRandom);
    // TLS 1.3 in mbedTLS needs PSA crypto. TLS 1.2 is enough for each server.
    mbedtls_ssl_conf_max_tls_version(&_config, MBEDTLS_SSL_VERSION_TLS1_2);
    int result = mbedtls_ssl_setup(&_ssl, &_config);
    if (result == 0) result = mbedtls_ssl_set_hostname(&_ssl, host.UTF8String);
    mbedtls_ssl_set_bio(&_ssl, &_socket, ZLSend, ZLReceive, NULL);
    NSString *key = [NSString stringWithFormat:@"%@:%d", host, port];
    NSMutableDictionary *sessions = ZLSessionTable();
    @synchronized (sessions) {
        mbedtls_ssl_session *saved = [sessions[key] pointerValue];
        // mbedtls_ssl_set_session copies the session.
        if (result == 0 && saved) mbedtls_ssl_set_session(&_ssl, saved);
    }
    NSDate *start = [NSDate date];
    while (result == 0 || result == MBEDTLS_ERR_SSL_WANT_READ || result == MBEDTLS_ERR_SSL_WANT_WRITE) {
        result = mbedtls_ssl_handshake(&_ssl);
        if (result == 0) break;
    }
    if (result != 0) {
        // A bad saved session must not stop the next connection.
        @synchronized (sessions) {
            mbedtls_ssl_session *saved = [sessions[key] pointerValue];
            if (saved) {
                mbedtls_ssl_session_free(saved);
                free(saved);
                [sessions removeObjectForKey:key];
            }
        }
        if (error) *error = ZLTLSError(result, [NSString stringWithFormat:@"The secure connection to %@ failed.", host]);
        return NO;
    }
    ZLLog(@"tls %@ %.2f s", host, -[start timeIntervalSinceNow]);
    uint32_t flags = mbedtls_ssl_get_verify_result(&_ssl);
    if (flags != 0 && ![trust isTrusted:host]) {
        char reason[256] = {0};
        mbedtls_x509_crt_verify_info(reason, sizeof(reason), "", flags);
        NSString *text = [NSString stringWithFormat:@"The certificate of %@ is not valid: %@", host,
                                                    [[NSString stringWithUTF8String:reason] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
        if (error) {
            *error = [NSError errorWithDomain:ZLErrorDomain code:ZLErrorUntrustedHost
                                     userInfo:@{ NSLocalizedDescriptionKey: text, ZLUntrustedHostKey: host }];
        }
        return NO;
    }
    mbedtls_ssl_session *session = malloc(sizeof(mbedtls_ssl_session));
    mbedtls_ssl_session_init(session);
    if (mbedtls_ssl_get_session(&_ssl, session) == 0) {
        @synchronized (sessions) {
            mbedtls_ssl_session *old = [sessions[key] pointerValue];
            if (old) {
                mbedtls_ssl_session_free(old);
                free(old);
            }
            sessions[key] = [NSValue valueWithPointer:session];
        }
    } else {
        mbedtls_ssl_session_free(session);
        free(session);
    }
    return YES;
}

- (void)dealloc {
    [self close];
    [self closeSocket];
    if (_tls) {
        mbedtls_ssl_free(&_ssl);
        mbedtls_ssl_config_free(&_config);
    }
}

- (BOOL)writeData:(NSData *)data error:(NSError **)error {
    const uint8_t *bytes = data.bytes;
    size_t left = data.length;
    while (left > 0) {
        if (self.closed) {
            if (error) *error = ZLMakeError(ZLErrorCancelled, @"The connection is closed.");
            return NO;
        }
        int n;
        if (self.tls) {
            n = mbedtls_ssl_write(&_ssl, bytes, left);
            if (n == MBEDTLS_ERR_SSL_WANT_WRITE || n == MBEDTLS_ERR_SSL_WANT_READ) continue;
        } else {
            n = (int)send(self.socket, bytes, left, 0);
            if (n < 0 && errno == EINTR) continue;
        }
        if (n <= 0) {
            if (error) *error = ZLMakeError(ZLErrorMedia, @"The app cannot send the request.");
            return NO;
        }
        bytes += n;
        left -= (size_t)n;
    }
    return YES;
}

- (NSInteger)read:(uint8_t *)bytes length:(NSUInteger)length error:(NSError **)error {
    while (YES) {
        if (self.closed) {
            if (error) *error = ZLMakeError(ZLErrorCancelled, @"The connection is closed.");
            return -1;
        }
        if (self.tls) {
            int n = mbedtls_ssl_read(&_ssl, bytes, length);
            if (n == MBEDTLS_ERR_SSL_WANT_READ || n == MBEDTLS_ERR_SSL_WANT_WRITE) continue;
            if (n == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY || n == 0) return 0;
            if (n == MBEDTLS_ERR_SSL_TIMEOUT) {
                if (error) *error = ZLMakeError(ZLErrorTimeout, @"The server stopped sending data.");
                return -1;
            }
            if (n < 0) {
                if (error) *error = self.closed ? ZLMakeError(ZLErrorCancelled, @"The connection is closed.")
                                                : ZLTLSError(n, @"The secure connection failed.");
                return -1;
            }
            return n;
        }
        ssize_t n = recv(self.socket, bytes, length, 0);
        if (n >= 0) return n;
        if (errno == EINTR) continue;
        if (error) {
            *error = (errno == EAGAIN || errno == EWOULDBLOCK) ? ZLMakeError(ZLErrorTimeout, @"The server stopped sending data.")
                                                               : ZLMakeError(ZLErrorMedia, @"The connection failed.");
        }
        return -1;
    }
}

- (void)close {
    @synchronized (self) {
        if (self.closed) return;
        self.closed = YES;
        // shutdown stops a read that waits on another thread.
        if (self.socket >= 0) shutdown(self.socket, SHUT_RDWR);
    }
    // The socket closes in dealloc, after the last read stops using it.
}

- (void)closeSocket {
    if (_socket >= 0) close(_socket);
    _socket = -1;
}

@end
