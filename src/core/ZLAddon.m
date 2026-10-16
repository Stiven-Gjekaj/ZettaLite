#import "ZLAddon.h"
#import "ZLJSON.h"

NSString *ZLAddonEscape(NSString *value) {
    return (__bridge_transfer NSString *)CFURLCreateStringByAddingPercentEscapes(
        NULL, (__bridge CFStringRef)value, CFSTR("!*'()"), CFSTR(":/?#[]@$&+,;=% \"<>{}|\\^`"), kCFStringEncodingUTF8);
}

NSString *ZLAddonEscapeID(NSString *identifier) {
    return (__bridge_transfer NSString *)CFURLCreateStringByAddingPercentEscapes(
        NULL, (__bridge CFStringRef)identifier, CFSTR(":"), CFSTR("/?#[]@$&+,;=% \"<>{}|\\^`"), kCFStringEncodingUTF8);
}

@implementation ZLCatalogExtra
@end

@implementation ZLCatalog

- (ZLCatalogExtra *)extraNamed:(NSString *)name {
    for (ZLCatalogExtra *extra in self.extras) {
        if ([extra.name isEqualToString:name]) return extra;
    }
    return nil;
}

- (BOOL)supportsSearch {
    return [self extraNamed:@"search"] != nil;
}

- (BOOL)needsExtra {
    for (ZLCatalogExtra *extra in self.extras) {
        if (extra.required) return YES;
    }
    return NO;
}

- (NSURL *)URLWithExtras:(NSDictionary *)extras {
    NSString *path = [NSString stringWithFormat:@"catalog/%@/%@", ZLAddonEscape(self.type), ZLAddonEscapeID(self.identifier)];
    NSMutableArray *pairs = [NSMutableArray array];
    // The order of the extras of the manifest, then the others.
    NSMutableArray *names = [NSMutableArray array];
    for (ZLCatalogExtra *extra in self.extras) [names addObject:extra.name];
    for (NSString *name in [extras.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        if (![names containsObject:name]) [names addObject:name];
    }
    for (NSString *name in names) {
        NSString *value = extras[name];
        if (value.length) [pairs addObject:[NSString stringWithFormat:@"%@=%@", ZLAddonEscape(name), ZLAddonEscape(value)]];
    }
    if (pairs.count) path = [path stringByAppendingFormat:@"/%@", [pairs componentsJoinedByString:@"&"]];
    return [NSURL URLWithString:[path stringByAppendingString:@".json"] relativeToURL:self.addon.baseURL].absoluteURL;
}

- (NSString *)key {
    return [NSString stringWithFormat:@"%@|%@|%@", self.addon.manifestURL.absoluteString, self.type, self.identifier];
}

@end

@implementation ZLAddonResource
@end

@implementation ZLAddon

+ (instancetype)addonWithManifest:(NSDictionary *)manifest URL:(NSURL *)url {
    if (![manifest isKindOfClass:[NSDictionary class]]) return nil;
    ZLAddon *addon = [ZLAddon new];
    addon.manifest = manifest;
    addon.manifestURL = url;
    // The base URL ends with "/", so that relative paths go below it.
    NSString *text = url.absoluteString;
    NSRange query = [text rangeOfString:@"?"];
    if (query.location != NSNotFound) text = [text substringToIndex:query.location];
    if ([text hasSuffix:@"/manifest.json"]) text = [text substringToIndex:text.length - @"manifest.json".length];
    else if (![text hasSuffix:@"/"]) text = [text stringByAppendingString:@"/"];
    addon.baseURL = [NSURL URLWithString:text];
    addon.identifier = ZLJSONString(manifest, @"id") ?: text;
    addon.name = ZLJSONString(manifest, @"name") ?: url.host;
    addon.version = ZLJSONString(manifest, @"version");
    addon.summary = ZLJSONString(manifest, @"description");
    NSString *logo = ZLJSONString(manifest, @"logo");
    addon.logo = logo ? [NSURL URLWithString:logo] : nil;
    addon.types = ZLJSONStrings(manifest, @"types");
    addon.idPrefixes = ZLJSONArray(manifest, @"idPrefixes") ? ZLJSONStrings(manifest, @"idPrefixes") : nil;
    addon.configurationRequired = [ZLJSONNumber(ZLJSONDictionary(manifest, @"behaviorHints"), @"configurationRequired") boolValue];

    NSMutableArray *catalogs = [NSMutableArray array];
    for (NSDictionary *item in ZLJSONArray(manifest, @"catalogs")) {
        NSString *type = ZLJSONString(item, @"type");
        NSString *identifier = ZLJSONString(item, @"id");
        if (!type || !identifier) continue;
        ZLCatalog *catalog = [ZLCatalog new];
        catalog.addon = addon;
        catalog.type = type;
        catalog.identifier = identifier;
        catalog.name = ZLJSONString(item, @"name") ?: identifier;
        NSMutableArray *extras = [NSMutableArray array];
        for (NSDictionary *value in ZLJSONArray(item, @"extra")) {
            NSString *name = ZLJSONString(value, @"name");
            if (!name) continue;
            ZLCatalogExtra *extra = [ZLCatalogExtra new];
            extra.name = name;
            extra.required = [ZLJSONNumber(value, @"isRequired") boolValue];
            extra.options = ZLJSONStrings(value, @"options");
            [extras addObject:extra];
        }
        // The old form of the protocol: extraSupported and extraRequired.
        NSArray *required = ZLJSONStrings(item, @"extraRequired");
        for (NSString *name in ZLJSONStrings(item, @"extraSupported")) {
            BOOL known = NO;
            for (ZLCatalogExtra *extra in extras) known = known || [extra.name isEqualToString:name];
            if (known) continue;
            ZLCatalogExtra *extra = [ZLCatalogExtra new];
            extra.name = name;
            extra.required = [required containsObject:name];
            [extras addObject:extra];
        }
        catalog.extras = extras;
        [catalogs addObject:catalog];
    }
    addon.catalogs = catalogs;

    NSMutableArray *resources = [NSMutableArray array];
    for (id item in ZLJSONArray(manifest, @"resources")) {
        ZLAddonResource *resource = [ZLAddonResource new];
        if ([item isKindOfClass:[NSString class]]) {
            resource.name = item;
        } else if ([item isKindOfClass:[NSDictionary class]] && ZLJSONString(item, @"name")) {
            resource.name = ZLJSONString(item, @"name");
            resource.types = ZLJSONArray(item, @"types") ? ZLJSONStrings(item, @"types") : nil;
            resource.idPrefixes = ZLJSONArray(item, @"idPrefixes") ? ZLJSONStrings(item, @"idPrefixes") : nil;
        } else {
            continue;
        }
        [resources addObject:resource];
    }
    addon.resources = resources;
    return addon;
}

- (BOOL)supportsResource:(NSString *)name type:(NSString *)type identifier:(NSString *)identifier {
    for (ZLAddonResource *resource in self.resources) {
        if (![resource.name isEqualToString:name]) continue;
        NSArray *types = resource.types ?: self.types;
        if (types.count && type && ![types containsObject:type]) continue;
        NSArray *prefixes = resource.idPrefixes ?: self.idPrefixes;
        if (prefixes.count && identifier) {
            BOOL match = NO;
            for (NSString *prefix in prefixes) match = match || [identifier hasPrefix:prefix];
            if (!match) continue;
        }
        return YES;
    }
    return NO;
}

- (NSURL *)URLForResource:(NSString *)resource type:(NSString *)type identifier:(NSString *)identifier {
    NSString *path = [NSString stringWithFormat:@"%@/%@/%@.json", resource, ZLAddonEscape(type), ZLAddonEscapeID(identifier)];
    return [NSURL URLWithString:path relativeToURL:self.baseURL].absoluteURL;
}

@end
