#import "ZLStore.h"

@interface ZLStore ()
@property (nonatomic, copy) NSString *directory;
@property (nonatomic, strong) NSMutableDictionary *cache;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation ZLStore

+ (instancetype)shared {
    static ZLStore *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
        shared = [[ZLStore alloc] initWithDirectory:[support stringByAppendingPathComponent:@"ZettaLite"]];
    });
    return shared;
}

- (instancetype)initWithDirectory:(NSString *)directory {
    if ((self = [super init])) {
        _directory = [directory copy];
        _cache = [NSMutableDictionary dictionary];
        _queue = dispatch_queue_create("ZLStore", DISPATCH_QUEUE_SERIAL);
        [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    return self;
}

- (NSString *)pathFor:(NSString *)name {
    return [self.directory stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"json"]];
}

- (id)objectNamed:(NSString *)name {
    @synchronized (self.cache) {
        id cached = self.cache[name];
        if (cached) return cached == [NSNull null] ? nil : cached;
        NSData *data = [NSData dataWithContentsOfFile:[self pathFor:name]];
        id object = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:NULL] : nil;
        self.cache[name] = object ?: [NSNull null];
        return object;
    }
}

- (void)setObject:(id)object named:(NSString *)name {
    NSData *data = object ? [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL] : nil;
    @synchronized (self.cache) {
        // Keep a copy, so that a later change of the object does not change the store.
        self.cache[name] = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:NULL]
                                : [NSNull null];
    }
    NSString *path = [self pathFor:name];
    dispatch_async(self.queue, ^{
        if (data) [data writeToFile:path atomically:YES];
        else [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    });
}

- (void)flush {
    dispatch_sync(self.queue, ^{});
}

@end
