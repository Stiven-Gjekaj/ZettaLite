#import "ZLTest.h"
#import "ZLTrust.h"

// User defaults in memory, so that the tests do not change the real ones.
@interface ZLMemoryDefaults : NSUserDefaults
@property (nonatomic, strong) NSMutableDictionary *values;
@end

@implementation ZLMemoryDefaults

- (id)objectForKey:(NSString *)key {
    return self.values[key];
}

- (NSArray *)arrayForKey:(NSString *)key {
    id value = self.values[key];
    return [value isKindOfClass:[NSArray class]] ? value : nil;
}

- (void)setObject:(id)value forKey:(NSString *)key {
    if (!self.values) self.values = [NSMutableDictionary dictionary];
    if (value) self.values[key] = value;
    else [self.values removeObjectForKey:key];
}

@end

ZL_TEST(test_trust_keeps_hosts_in_lower_case) {
    ZLTrust *trust = [[ZLTrust alloc] initWithDefaults:[ZLMemoryDefaults new]];
    ZL_EXPECT(![trust isTrusted:@"example.org"]);
    [trust trustHost:@"Example.ORG"];
    [trust trustHost:@"example.org"];
    ZL_EXPECT([trust isTrusted:@"EXAMPLE.org"]);
    ZL_EQUAL_INT([trust hosts].count, 1);
    [trust forgetHost:@"example.org"];
    ZL_EXPECT(![trust isTrusted:@"example.org"]);
}

ZL_TEST(test_trust_refuses_an_empty_host) {
    ZLTrust *trust = [[ZLTrust alloc] initWithDefaults:[ZLMemoryDefaults new]];
    [trust trustHost:@""];
    ZL_EQUAL_INT([trust hosts].count, 0);
    ZL_EXPECT(![trust acceptTrust:NULL host:@""]);
}
