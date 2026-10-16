// A Stremio addon, read from its manifest.json. The addon protocol is plain
// HTTP with JSON:
//   BASE/manifest.json
//   BASE/catalog/TYPE/ID.json or BASE/catalog/TYPE/ID/EXTRA.json
//   BASE/meta/TYPE/ID.json
//   BASE/stream/TYPE/ID.json
//   BASE/subtitles/TYPE/ID.json
// BASE is the URL of the manifest without "/manifest.json".

#import <Foundation/Foundation.h>

@class ZLAddon;

// A value that a catalog accepts, for example "search" or "genre".
@interface ZLCatalogExtra : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) BOOL required;
@property (nonatomic, copy) NSArray *options;
@end

@interface ZLCatalog : NSObject
@property (nonatomic, weak) ZLAddon *addon;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSArray *extras;
- (ZLCatalogExtra *)extraNamed:(NSString *)name;
// YES when the catalog has a search extra.
- (BOOL)supportsSearch;
// YES when the catalog needs an extra, so it cannot be a row of Home.
- (BOOL)needsExtra;
// The URL of a page. extras is for example @{@"search": @"matrix", @"skip": @"100"}.
- (NSURL *)URLWithExtras:(NSDictionary *)extras;
// A key that is the same for the same catalog of the same addon.
- (NSString *)key;
@end

@interface ZLAddonResource : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSArray *types;  // nil: the types of the addon.
@property (nonatomic, copy) NSArray *idPrefixes;  // nil: the prefixes of the addon, or all.
@end

@interface ZLAddon : NSObject
@property (nonatomic, strong) NSURL *manifestURL;
@property (nonatomic, strong) NSURL *baseURL;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSString *summary;
@property (nonatomic, strong) NSURL *logo;
@property (nonatomic, copy) NSArray *types;
@property (nonatomic, copy) NSArray *idPrefixes;
@property (nonatomic, copy) NSArray *catalogs;
@property (nonatomic, copy) NSArray *resources;
@property (nonatomic) BOOL configurationRequired;
// The manifest as it came, so that the app can keep it on the phone.
@property (nonatomic, copy) NSDictionary *manifest;

+ (instancetype)addonWithManifest:(NSDictionary *)manifest URL:(NSURL *)url;
// YES when the addon gives the resource for this type and ID.
- (BOOL)supportsResource:(NSString *)resource type:(NSString *)type identifier:(NSString *)identifier;
- (NSURL *)URLForResource:(NSString *)resource type:(NSString *)type identifier:(NSString *)identifier;
@end

// Encodes a value for a path of the addon protocol, as encodeURIComponent
// of JavaScript does.
NSString *ZLAddonEscape(NSString *value);
// Encodes an ID. It keeps ":" as it is, as the Stremio app does, for example
// in tt0944947:1:2.
NSString *ZLAddonEscapeID(NSString *identifier);
