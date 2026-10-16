// Loads the addons of the source list, and asks them for catalogs, titles,
// and streams. Each request runs in the background. Each completion comes on
// the main thread. Use this class on the main thread only.

#import <Foundation/Foundation.h>
#import "ZLAddon.h"
#import "ZLMeta.h"

extern NSString *const ZLAddonsDidChangeNotification;

// Fetches a URL and reads it as JSON in the background.
void ZLFetchJSON(NSURL *url, void (^completion)(id json, NSError *error));

@interface ZLAddonManager : NSObject

+ (instancetype)shared;

// The addons, in the order of the source list. An addon that did not load
// yet is not in the list.
@property (nonatomic, readonly) NSArray *addons;
// The sources whose manifest failed to load, with the error text.
@property (nonatomic, readonly) NSDictionary *failures;

// Loads the manifests again. The manifests on the phone show at once.
- (void)reload;

// The catalogs that can be rows of Home: the ones with no required extra.
- (NSArray *)homeCatalogs;

- (void)loadCatalog:(ZLCatalog *)catalog extras:(NSDictionary *)extras
         completion:(void (^)(NSArray *metas, NSError *error))completion;

// Asks each catalog with search. Each result comes when it arrives.
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
