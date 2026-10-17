#import "ZLAddonManager.h"
#import "ZLHTTPStream.h"
#import "ZLJSON.h"
#import "ZLLog.h"
#import "ZLSources.h"
#import "ZLStore.h"
#import "ZLTrust.h"

NSString *const ZLAddonsDidChangeNotification = @"ZLAddonsDidChange";

// The answers of a catalog stay this long in memory.
static const NSTimeInterval ZLCatalogLifetime = 10 * 60;
// A manifest changes seldom. The app asks again after this time.
static const NSTimeInterval ZLManifestLifetime = 6 * 3600;

static NSOperationQueue *ZLNetworkQueue(void) {
    static NSOperationQueue *queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = [NSOperationQueue new];
        // The A5 chip does a TLS handshake in about half a second. More
        // requests at the same time only slow each other.
        queue.maxConcurrentOperationCount = 4;
    });
    return queue;
}

void ZLFetchJSON(NSURL *url, void (^completion)(id json, NSError *error)) {
    ZLFetchJSONWithPriority(url, ZLFetchNormal, completion);
}

NSOperation *ZLFetchJSONWithPriority(NSURL *url, ZLFetchPriority priority, void (^completion)(id json, NSError *error)) {
    NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
        NSError *error = nil;
        NSData *data = [ZLHTTPStream fetch:url headers:@{ @"Accept": @"application/json" } finalURL:NULL error:&error];
        id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
        if (!json && !error) error = ZLMakeError(ZLErrorMedia, @"The answer is not JSON.");
        if (error) ZLLog(@"json %@: %@", url, error.localizedDescription);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(json, json ? nil : error); });
    }];
    operation.queuePriority = priority == ZLFetchHigh ? NSOperationQueuePriorityHigh : NSOperationQueuePriorityNormal;
    [ZLNetworkQueue() addOperation:operation];
    return operation;
}

@interface ZLAddonManager ()
@property (nonatomic, strong) ZLStore *store;
@property (nonatomic, strong) ZLSourceList *sources;
@property (nonatomic) NSUInteger searchGeneration;
@property (nonatomic, strong) NSMutableArray *searchOperations;
@property (nonatomic, strong) NSArray *addons;
@property (nonatomic, strong) NSDictionary *failures;
@property (nonatomic, strong) NSMutableDictionary *catalogCache;
@property (nonatomic) NSUInteger generation;
// The requests that wait for the manifests that load now.
@property (nonatomic, strong) NSMutableArray *waiting;
@property (nonatomic) BOOL loading;
@end

@implementation ZLAddonManager

+ (instancetype)shared {
    static ZLAddonManager *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[ZLAddonManager alloc] initWithStore:[ZLStore shared] sources:[ZLSourceList shared]];
    });
    return shared;
}

- (instancetype)initWithStore:(ZLStore *)store sources:(ZLSourceList *)sources {
    if ((self = [super init])) {
        _store = store;
        _sources = sources;
        _addons = @[];
        _failures = @{};
        _catalogCache = [NSMutableDictionary dictionary];
        _waiting = [NSMutableArray array];
        _searchOperations = [NSMutableArray array];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload)
                                                     name:ZLSourcesDidChangeNotification object:sources];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Manifests

- (void)reload {
    [self reloadAll:NO];
}

- (void)refresh {
    [self reloadAll:YES];
}

- (void)reloadAll:(BOOL)all {
    NSUInteger generation = ++self.generation;
    NSArray *sources = [self.sources sourcesOfKind:ZLSourceAddon];
    NSDictionary *saved = [self.store objectNamed:@"manifests"] ?: @{};
    NSDictionary *dates = [self.store objectNamed:@"manifestDates"] ?: @{};
    NSMutableDictionary *manifests = [NSMutableDictionary dictionary];
    NSMutableDictionary *fetched = [NSMutableDictionary dictionary];
    NSMutableArray *old = [NSMutableArray array];
    double now = [[NSDate date] timeIntervalSince1970];
    for (ZLSource *source in sources) {
        NSString *key = source.URL.absoluteString;
        NSDictionary *manifest = saved[key];
        if ([manifest isKindOfClass:[NSDictionary class]]) manifests[key] = manifest;
        if ([dates[key] isKindOfClass:[NSNumber class]]) fetched[key] = dates[key];
        if (all || !manifests[key] || now - [fetched[key] doubleValue] > ZLManifestLifetime) [old addObject:source];
    }
    [self buildFrom:manifests sources:sources failures:@{}];
    if (!old.count) {
        [self finishLoading];
        return;
    }
    // A request for a manifest that is not on the phone waits for the load.
    self.loading = manifests.count < sources.count;

    NSDate *start = [NSDate date];
    __block NSUInteger left = old.count;
    NSMutableDictionary *failures = [NSMutableDictionary dictionary];
    for (ZLSource *source in old) {
        NSString *key = source.URL.absoluteString;
        // A refresh of a manifest on the phone must not hold back the requests
        // that the viewer waits for. A new manifest is one of them.
        ZLFetchPriority priority = manifests[key] ? ZLFetchNormal : ZLFetchHigh;
        ZLFetchJSONWithPriority(source.URL, priority, ^(id json, NSError *error) {
            if (generation != self.generation) return;
            if ([json isKindOfClass:[NSDictionary class]] && (json[@"id"] || json[@"catalogs"] || json[@"resources"])) {
                manifests[key] = json;
                fetched[key] = @([[NSDate date] timeIntervalSince1970]);
            } else if (!manifests[key]) {
                failures[key] = error.localizedDescription ?: @"The link does not give an addon manifest.";
            }
            if (--left == 0) {
                ZLLog(@"time manifests %lu of %lu: %.2f s", (unsigned long)old.count, (unsigned long)sources.count,
                      -[start timeIntervalSinceNow]);
                [self.store setObject:manifests named:@"manifests"];
                [self.store setObject:fetched named:@"manifestDates"];
                [self buildFrom:manifests sources:sources failures:failures];
                [self finishLoading];
            }
        });
    }
}

- (void)finishLoading {
    self.loading = NO;
    NSArray *waiting = [self.waiting copy];
    [self.waiting removeAllObjects];
    for (void (^block)(void) in waiting) block();
}

// Runs the block now, or after the manifests that load now.
- (void)whenReady:(void (^)(void))block {
    if (self.loading) [self.waiting addObject:[block copy]];
    else block();
}

- (void)buildFrom:(NSDictionary *)manifests sources:(NSArray *)sources failures:(NSDictionary *)failures {
    NSMutableArray *addons = [NSMutableArray array];
    for (ZLSource *source in sources) {
        ZLAddon *addon = [ZLAddon addonWithManifest:manifests[source.URL.absoluteString] URL:source.URL];
        if (addon) [addons addObject:addon];
    }
    self.addons = addons;
    self.failures = failures;
    [[NSNotificationCenter defaultCenter] postNotificationName:ZLAddonsDidChangeNotification object:self];
}

- (NSArray *)homeCatalogs {
    NSMutableArray *catalogs = [NSMutableArray array];
    for (ZLAddon *addon in self.addons) {
        for (ZLCatalog *catalog in addon.catalogs) {
            if (!catalog.needsExtra) [catalogs addObject:catalog];
        }
    }
    return catalogs;
}

#pragma mark - Requests

static NSArray *ZLMetasFrom(id json, ZLAddon *addon) {
    NSMutableArray *metas = [NSMutableArray array];
    for (NSDictionary *item in ZLJSONArray(json, @"metas")) {
        ZLMeta *meta = [ZLMeta metaWithJSON:item];
        if (!meta) continue;
        meta.addon = addon;
        [metas addObject:meta];
    }
    return metas;
}

- (void)loadCatalog:(ZLCatalog *)catalog extras:(NSDictionary *)extras
         completion:(void (^)(NSArray *metas, NSError *error))completion {
    [self fetchCatalog:catalog extras:extras completion:completion];
}

// Returns the operation of the request, or nil when the answer was in memory.
- (NSOperation *)fetchCatalog:(ZLCatalog *)catalog extras:(NSDictionary *)extras
                   completion:(void (^)(NSArray *metas, NSError *error))completion {
    NSURL *url = [catalog URLWithExtras:extras];
    NSString *key = url.absoluteString;
    NSDictionary *cached = self.catalogCache[key];
    if (cached && -[cached[@"date"] timeIntervalSinceNow] < ZLCatalogLifetime) {
        completion(cached[@"metas"], nil);
        return nil;
    }
    ZLAddon *addon = catalog.addon;
    NSDate *start = [NSDate date];
    return ZLFetchJSONWithPriority(url, ZLFetchNormal, ^(id json, NSError *error) {
        NSArray *metas = json ? ZLMetasFrom(json, addon) : nil;
        if (!extras.count) ZLLog(@"time catalog %@ %@: %.2f s", addon.name, catalog.name, -[start timeIntervalSinceNow]);
        if (metas) self.catalogCache[key] = @{ @"date": [NSDate date], @"metas": metas };
        completion(metas ?: @[], error);
    });
}

- (void)search:(NSString *)text each:(void (^)(ZLCatalog *, NSArray *))each done:(void (^)(void))done {
    // A new search stops the requests of the last one that did not start.
    NSUInteger generation = ++self.searchGeneration;
    for (NSOperation *operation in self.searchOperations) [operation cancel];
    [self.searchOperations removeAllObjects];
    [self searchNow:text generation:generation each:each done:done];
}

- (void)searchNow:(NSString *)text generation:(NSUInteger)generation
             each:(void (^)(ZLCatalog *, NSArray *))each done:(void (^)(void))done {
    if (self.loading) {
        [self whenReady:^{
            if (generation == self.searchGeneration) [self searchNow:text generation:generation each:each done:done];
        }];
        return;
    }
    NSMutableArray *catalogs = [NSMutableArray array];
    for (ZLAddon *addon in self.addons) {
        for (ZLCatalog *catalog in addon.catalogs) {
            if (catalog.supportsSearch) [catalogs addObject:catalog];
        }
    }
    __block NSUInteger left = catalogs.count;
    if (!left) {
        done();
        return;
    }
    NSDate *start = [NSDate date];
    __block BOOL first = YES;
    NSUInteger total = catalogs.count;
    for (ZLCatalog *catalog in catalogs) {
        NSOperation *operation = [self fetchCatalog:catalog extras:@{ @"search": text } completion:^(NSArray *metas, NSError *error) {
            if (generation != self.searchGeneration) return;
            if (metas.count && first) {
                first = NO;
                ZLLog(@"time search first result: %.2f s", -[start timeIntervalSinceNow]);
            }
            if (metas.count) each(catalog, metas);
            if (--left == 0) {
                ZLLog(@"time search %lu catalogs: %.2f s", (unsigned long)total, -[start timeIntervalSinceNow]);
                [self.searchOperations removeAllObjects];
                done();
            }
        }];
        if (operation) [self.searchOperations addObject:operation];
    }
}

- (void)loadMeta:(NSString *)type identifier:(NSString *)identifier
      completion:(void (^)(ZLMeta *, NSError *))completion {
    NSDate *start = [NSDate date];
    void (^done)(ZLMeta *, NSError *) = ^(ZLMeta *meta, NSError *error) {
        ZLLog(@"time meta %@: %.2f s", identifier, -[start timeIntervalSinceNow]);
        completion(meta, error);
    };
    [self loadMetaNow:type identifier:identifier completion:done];
}

- (void)loadMetaNow:(NSString *)type identifier:(NSString *)identifier
         completion:(void (^)(ZLMeta *, NSError *))completion {
    if (self.loading) {
        [self whenReady:^{ [self loadMetaNow:type identifier:identifier completion:completion]; }];
        return;
    }
    NSMutableArray *addons = [NSMutableArray array];
    for (ZLAddon *addon in self.addons) {
        if ([addon supportsResource:@"meta" type:type identifier:identifier]) [addons addObject:addon];
    }
    [self loadMetaFrom:addons type:type identifier:identifier error:nil completion:completion];
}

- (void)loadMetaFrom:(NSMutableArray *)addons type:(NSString *)type identifier:(NSString *)identifier
               error:(NSError *)lastError completion:(void (^)(ZLMeta *, NSError *))completion {
    if (!addons.count) {
        completion(nil, lastError ?: ZLMakeError(ZLErrorMedia, @"No addon gives the details of this title."));
        return;
    }
    ZLAddon *addon = addons.firstObject;
    [addons removeObjectAtIndex:0];
    ZLFetchJSONWithPriority([addon URLForResource:@"meta" type:type identifier:identifier], ZLFetchHigh, ^(id json, NSError *error) {
        ZLMeta *meta = [ZLMeta metaWithJSON:ZLJSONDictionary(json, @"meta")];
        if (meta) {
            meta.addon = addon;
            completion(meta, nil);
        } else {
            [self loadMetaFrom:addons type:type identifier:identifier error:error completion:completion];
        }
    });
}

- (void)loadStreams:(NSString *)type identifier:(NSString *)identifier
               each:(void (^)(ZLAddon *, NSArray *, NSError *))each
               done:(void (^)(void))done {
    if (self.loading) {
        [self whenReady:^{ [self loadStreams:type identifier:identifier each:each done:done]; }];
        return;
    }
    NSMutableArray *addons = [NSMutableArray array];
    for (ZLAddon *addon in self.addons) {
        if ([addon supportsResource:@"stream" type:type identifier:identifier]) [addons addObject:addon];
    }
    __block NSUInteger left = addons.count;
    if (!left) {
        done();
        return;
    }
    for (ZLAddon *addon in addons) {
        ZLFetchJSONWithPriority([addon URLForResource:@"stream" type:type identifier:identifier], ZLFetchHigh, ^(id json, NSError *error) {
            NSMutableArray *streams = [NSMutableArray array];
            for (NSDictionary *item in ZLJSONArray(json, @"streams")) {
                ZLStream *stream = [ZLStream streamWithJSON:item];
                if (!stream) continue;
                stream.addon = addon;
                stream.addonName = addon.name;
                [streams addObject:stream];
            }
            each(addon, streams, json ? nil : error);
            if (--left == 0) done();
        });
    }
}

- (void)loadSubtitles:(NSString *)type identifier:(NSString *)identifier completion:(void (^)(NSArray *))completion {
    if (self.loading) {
        [self whenReady:^{ [self loadSubtitles:type identifier:identifier completion:completion]; }];
        return;
    }
    NSMutableArray *addons = [NSMutableArray array];
    for (ZLAddon *addon in self.addons) {
        if ([addon supportsResource:@"subtitles" type:type identifier:identifier]) [addons addObject:addon];
    }
    __block NSUInteger left = addons.count;
    NSMutableArray *subtitles = [NSMutableArray array];
    if (!left) {
        completion(subtitles);
        return;
    }
    for (ZLAddon *addon in addons) {
        ZLFetchJSONWithPriority([addon URLForResource:@"subtitles" type:type identifier:identifier], ZLFetchHigh, ^(id json, NSError *error) {
            for (NSDictionary *item in ZLJSONArray(json, @"subtitles")) {
                if (ZLJSONString(item, @"url")) [subtitles addObject:item];
            }
            if (--left == 0) completion(subtitles);
        });
    }
}

@end
