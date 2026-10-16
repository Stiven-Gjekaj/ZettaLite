// Keeps JSON values in files in Library/Application Support/ZettaLite.
// The writes go to the disk on a background queue.

#import <Foundation/Foundation.h>

@interface ZLStore : NSObject
+ (instancetype)shared;
// Tests give their own directory.
- (instancetype)initWithDirectory:(NSString *)directory;
- (id)objectNamed:(NSString *)name;
- (void)setObject:(id)object named:(NSString *)name;
// Waits until each write is on the disk.
- (void)flush;
- (NSString *)directory;
@end
