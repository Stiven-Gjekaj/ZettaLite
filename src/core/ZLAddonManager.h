// Loads the addons of the source list, and asks them for catalogs, titles,
// and streams. Each request runs in the background. Each completion comes on
// the main thread. Use this class on the main thread only.

#import <Foundation/Foundation.h>
#import "ZLAddon.h"
#import "ZLMeta.h"

extern NSString *const ZLAddonsDidChangeNotification;

@class ZLSourceList, ZLStore;

typedef NS_ENUM(NSInteger, ZLFetchPriority) {
    // Catalogs and search. A search asks many catalogs at the same time.
    ZLFetchNormal,
    // A request that the viewer waits for: a manifest, a title, the streams,
    // or the subtitles. It goes before the normal requests that wait.
    ZLFetchHigh,
};

// Fetches a URL and reads it as JSON in the background, with normal priority.
void ZLFetchJSON(NSURL *url, void (^completion)(id json, NSError *error));
// Returns the operation. A cancel before it starts stops it, and then the
// completion does not come.
NSOperation *ZLFetchJSONWithPriority(NSURL *url, ZLFetchPriority priority, void (^completion)(id json, NSError *error));

@interface ZLAddonManager : NSObject

+ (instancetype)shared;
// Tests give their own store and source list.
- (instancetype)initWithStore:(ZLStore *)store sources:(ZLSourceList *)sources;

// The addons, in the order of the source list. An addon that did not load
// yet is not in the list.
@property (nonatomic, readonly) NSArray *addons;
// The sources whose manifest failed to load, with the error text.
@property (nonatomic, readonly) NSDictionary *failures;

// Loads the manifests that are not on the phone or that are older than 6
// hours. The manifests on the phone show at once.
- (void)reload;
// Loads all the manifests again.
- (void)refresh;

// The catalogs that can be rows of Home: the ones with no required extra.
- (NSArray *)homeCatalogs;

- (void)loadCatalog:(ZLCatalog *)catalog extras:(NSDictionary *)extras
         completion:(void (^)(NSArray *metas, NSError *error))completion;

// Asks each catalog with search. Each result comes when it arrives. A new
// search stops the requests of the last one, and its blocks do not come.
- (void)search:(NSString *)text each:(void (^)(ZLCatalog *catalog, NSArray *metas))each done:(void (^)(void))done;

// Asks the addons with a meta resource for the type and the ID, in order,
// until one gives the title.
- (void)loadMeta:(NSString *)type identifier:(NSString *)identifier
      completion:(void (^)(ZLMeta *meta, NSError *error))completion;

// Asks all addons with a stream resource at the same time. Each answer comes
// when it arrives. done comes after the last one.
- (void)loadStreams:(NSString *)type identifier:(NSString *)identifier
               each:(void (^)(ZLAddon *addon, NSArray *streams, NSError *error))each
               done:(void (^)(void))done;

// Asks all addons with a subtitles resource at the same time.
- (void)loadSubtitles:(NSString *)type identifier:(NSString *)identifier
           completion:(void (^)(NSArray *subtitles))completion;

@end
