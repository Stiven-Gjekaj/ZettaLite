// Safe reads from JSON. An addon can send a value of the wrong type, so each
// read checks the type.

#import <Foundation/Foundation.h>

NSString *ZLJSONString(id dictionary, NSString *key);
NSNumber *ZLJSONNumber(id dictionary, NSString *key);
NSArray *ZLJSONArray(id dictionary, NSString *key);
NSDictionary *ZLJSONDictionary(id dictionary, NSString *key);
// A number or a string with a number, as an integer. fallback when missing.
NSInteger ZLJSONInteger(id dictionary, NSString *key, NSInteger fallback);
// Strings from an array that can also hold other values.
NSArray *ZLJSONStrings(id dictionary, NSString *key);
