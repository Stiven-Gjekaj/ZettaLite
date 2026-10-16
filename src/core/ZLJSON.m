#import "ZLJSON.h"

static id ZLJSONValue(id dictionary, NSString *key, Class type) {
    if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
    id value = dictionary[key];
    return [value isKindOfClass:type] ? value : nil;
}

NSString *ZLJSONString(id dictionary, NSString *key) {
    id value = ZLJSONValue(dictionary, key, [NSObject class]);
    if ([value isKindOfClass:[NSString class]]) return [value length] ? value : nil;
    if ([value isKindOfClass:[NSNumber class]]) return [value stringValue];
    return nil;
}

NSNumber *ZLJSONNumber(id dictionary, NSString *key) {
    id value = ZLJSONValue(dictionary, key, [NSObject class]);
    if ([value isKindOfClass:[NSNumber class]]) return value;
    if ([value isKindOfClass:[NSString class]]) {
        NSScanner *scanner = [NSScanner scannerWithString:value];
        double number = 0;
        if ([scanner scanDouble:&number]) return @(number);
    }
    return nil;
}

NSArray *ZLJSONArray(id dictionary, NSString *key) {
    return ZLJSONValue(dictionary, key, [NSArray class]);
}

NSDictionary *ZLJSONDictionary(id dictionary, NSString *key) {
    return ZLJSONValue(dictionary, key, [NSDictionary class]);
}

NSInteger ZLJSONInteger(id dictionary, NSString *key, NSInteger fallback) {
    NSNumber *number = ZLJSONNumber(dictionary, key);
    return number ? number.integerValue : fallback;
}

NSArray *ZLJSONStrings(id dictionary, NSString *key) {
    NSMutableArray *strings = [NSMutableArray array];
    for (id value in ZLJSONArray(dictionary, key)) {
        if ([value isKindOfClass:[NSString class]] && [value length]) [strings addObject:value];
    }
    return strings;
}
