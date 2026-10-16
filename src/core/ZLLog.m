#import "ZLLog.h"

// The log starts again from its second half when it is larger than this.
static const unsigned long long ZLLogLimit = 256 * 1024;

static NSString *ZLLogPath(void) {
    NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSString *folder = [caches stringByAppendingPathComponent:@"ZettaLite"];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    return [folder stringByAppendingPathComponent:@"log.txt"];
}

static dispatch_queue_t ZLLogQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("ZLLog", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

void ZLLog(NSString *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString *text = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"HH:mm:ss.SSS";
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [formatter stringFromDate:[NSDate date]], text];
    dispatch_async(ZLLogQueue(), ^{
        NSString *path = ZLLogPath();
        NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!file) {
            [[NSData data] writeToFile:path atomically:NO];
            file = [NSFileHandle fileHandleForWritingAtPath:path];
        }
        unsigned long long size = [file seekToEndOfFile];
        if (size > ZLLogLimit) {
            [file closeFile];
            NSData *old = [NSData dataWithContentsOfFile:path];
            [[old subdataWithRange:NSMakeRange(old.length / 2, old.length - old.length / 2)] writeToFile:path atomically:YES];
            file = [NSFileHandle fileHandleForWritingAtPath:path];
            [file seekToEndOfFile];
        }
        [file writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [file closeFile];
    });
}

NSString *ZLLogText(void) {
    __block NSString *text = nil;
    dispatch_sync(ZLLogQueue(), ^{
        text = [NSString stringWithContentsOfFile:ZLLogPath() encoding:NSUTF8StringEncoding error:NULL];
    });
    return text ?: @"";
}
