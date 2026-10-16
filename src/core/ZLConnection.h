// One TCP connection, with TLS from mbedTLS for https. The TLS of iOS 6
// has no AES-GCM and no ChaCha20, and it does not know the newer root
// certificates. mbedTLS has both, and it checks each certificate against the
// Mozilla root list in cacert.pem.
// The methods block. close can come from another thread.

#import <Foundation/Foundation.h>
#import "ZLTrust.h"

@interface ZLConnection : NSObject

// Connects and, for TLS, does the handshake and checks the certificate.
// A host that fails the check gives ZLErrorUntrustedHost, unless the user
// trusts it.
+ (instancetype)connectToHost:(NSString *)host port:(int)port tls:(BOOL)tls trust:(ZLTrust *)trust
                      timeout:(NSTimeInterval)timeout error:(NSError **)error;

- (BOOL)writeData:(NSData *)data error:(NSError **)error;
// Returns the number of bytes read, 0 at the end, or -1 on an error.
- (NSInteger)read:(uint8_t *)bytes length:(NSUInteger)length error:(NSError **)error;
- (void)close;

@end

// The file with the root certificates. The default is cacert.pem in the
// main bundle.
void ZLSetCertificateFile(NSString *path);
