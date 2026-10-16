// The hosts that the user trusts although their certificate fails the trust
// check of iOS 6. iOS 6 does not know newer root certificates, for example
// ISRG Root X1 of Let's Encrypt. The app asks the user one time for each host.
// It never trusts all hosts.

#import <Foundation/Foundation.h>
#import <Security/Security.h>

extern NSString *const ZLErrorDomain;

typedef NS_ENUM(NSInteger, ZLErrorCode) {
    ZLErrorUntrustedHost = 1,  // userInfo[ZLUntrustedHostKey] has the host.
    ZLErrorHTTPStatus = 2,
    ZLErrorTimeout = 3,
    ZLErrorMedia = 4,
    ZLErrorCancelled = 5,
};

extern NSString *const ZLUntrustedHostKey;

NSError *ZLMakeError(ZLErrorCode code, NSString *text);

@interface ZLTrust : NSObject

+ (instancetype)shared;

// Tests give their own defaults, so that they do not change the real ones.
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;

- (BOOL)isTrusted:(NSString *)host;
- (void)trustHost:(NSString *)host;
- (void)forgetHost:(NSString *)host;
- (NSArray *)hosts;

// YES if the system accepts the trust, or if the user trusts the host.
- (BOOL)acceptTrust:(SecTrustRef)trust host:(NSString *)host;

@end
