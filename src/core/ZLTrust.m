#import "ZLTrust.h"

NSString *const ZLErrorDomain = @"ZettaLite";
NSString *const ZLUntrustedHostKey = @"ZLUntrustedHost";

static NSString *const ZLTrustedHostsKey = @"ZLTrustedHosts";

NSError *ZLMakeError(ZLErrorCode code, NSString *text) {
    return [NSError errorWithDomain:ZLErrorDomain code:code userInfo:@{ NSLocalizedDescriptionKey: text ?: @"" }];
}

@interface ZLTrust ()
@property (nonatomic, strong) NSUserDefaults *defaults;
@end

@implementation ZLTrust

+ (instancetype)shared {
    static ZLTrust *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[ZLTrust alloc] initWithDefaults:[NSUserDefaults standardUserDefaults]]; });
    return shared;
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    if ((self = [super init])) _defaults = defaults;
    return self;
}

- (NSArray *)hosts {
    @synchronized (self) {
        return [self.defaults arrayForKey:ZLTrustedHostsKey] ?: @[];
    }
}

- (BOOL)isTrusted:(NSString *)host {
    return host.length && [[self hosts] containsObject:host.lowercaseString];
}

- (void)trustHost:(NSString *)host {
    if (!host.length || [self isTrusted:host]) return;
    @synchronized (self) {
        NSArray *hosts = [[self.defaults arrayForKey:ZLTrustedHostsKey] ?: @[] arrayByAddingObject:host.lowercaseString];
        [self.defaults setObject:hosts forKey:ZLTrustedHostsKey];
    }
}

- (void)forgetHost:(NSString *)host {
    @synchronized (self) {
        NSMutableArray *hosts = [[self.defaults arrayForKey:ZLTrustedHostsKey] mutableCopy];
        [hosts removeObject:host.lowercaseString];
        [self.defaults setObject:hosts ?: @[] forKey:ZLTrustedHostsKey];
    }
}

- (BOOL)acceptTrust:(SecTrustRef)trust host:(NSString *)host {
    SecTrustResultType result = kSecTrustResultInvalid;
    if (trust && SecTrustEvaluate(trust, &result) == errSecSuccess &&
        (result == kSecTrustResultProceed || result == kSecTrustResultUnspecified)) {
        return YES;
    }
    return [self isTrusted:host];
}

@end
