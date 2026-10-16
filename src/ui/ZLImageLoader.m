#import "ZLImageLoader.h"
#import <CommonCrypto/CommonDigest.h>
#import <ImageIO/ImageIO.h>
#import "ZLHTTPStream.h"

// The disk cache keeps this many bytes. Older files go first.
static const unsigned long long ZLDiskLimit = 60 * 1024 * 1024;

@interface ZLImageLoader ()
@property (nonatomic, strong) NSCache *images;
@property (nonatomic, strong) NSOperationQueue *queue;
@property (nonatomic, copy) NSString *folder;
@property (nonatomic, strong) NSMutableDictionary *waiting;  // URL -> handlers
@end

@implementation ZLImageLoader

+ (instancetype)shared {
    static ZLImageLoader *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [ZLImageLoader new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _images = [NSCache new];
        _images.totalCostLimit = 16 * 1024 * 1024;  // The iPhone 4S has 512 MB.
        _queue = [NSOperationQueue new];
        _queue.maxConcurrentOperationCount = 3;
        _waiting = [NSMutableDictionary dictionary];
        NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        _folder = [caches stringByAppendingPathComponent:@"ZettaLite/images"];
        [[NSFileManager defaultManager] createDirectoryAtPath:_folder withIntermediateDirectories:YES attributes:nil error:NULL];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(trimDisk)
                                                     name:UIApplicationDidEnterBackgroundNotification object:nil];
    }
    return self;
}

static NSString *ZLHash(NSString *text) {
    const char *bytes = text.UTF8String;
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(bytes, (CC_LONG)strlen(bytes), digest);
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

- (NSString *)keyFor:(NSURL *)url size:(CGSize)size {
    return [NSString stringWithFormat:@"%@|%d", url.absoluteString, (int)MAX(size.width, size.height)];
}

- (UIImage *)cachedImageForURL:(NSURL *)url size:(CGSize)size {
    return url ? [self.images objectForKey:[self keyFor:url size:size]] : nil;
}

// Decodes the image with its largest side at most pixels. ImageIO decodes a
// small JPEG directly, so a large poster uses little memory.
static UIImage *ZLDecode(NSData *data, CGFloat pixels, CGFloat scale) {
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) return nil;
    NSDictionary *options = @{ (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                               (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
                               (id)kCGImageSourceThumbnailMaxPixelSize: @(pixels) };
    CGImageRef image = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (!image) return nil;
    // Draw it one time here, so that the main thread does not decode it.
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, space,
                                                 kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    UIImage *result = nil;
    if (context) {
        CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
        CGImageRef drawn = CGBitmapContextCreateImage(context);
        CGContextRelease(context);
        result = [UIImage imageWithCGImage:drawn scale:scale orientation:UIImageOrientationUp];
        CGImageRelease(drawn);
    }
    CGImageRelease(image);
    return result;
}

- (void)loadURL:(NSURL *)url size:(CGSize)size handler:(void (^)(UIImage *))handler {
    if (!url) {
        handler(nil);
        return;
    }
    NSString *key = [self keyFor:url size:size];
    UIImage *cached = [self.images objectForKey:key];
    if (cached) {
        handler(cached);
        return;
    }
    NSMutableArray *handlers = self.waiting[key];
    if (handlers) {
        [handlers addObject:[handler copy]];
        return;
    }
    self.waiting[key] = [NSMutableArray arrayWithObject:[handler copy]];
    CGFloat scale = [UIScreen mainScreen].scale;
    CGFloat pixels = MAX(size.width, size.height) * scale;
    NSString *file = [self.folder stringByAppendingPathComponent:ZLHash(url.absoluteString)];
    [self.queue addOperationWithBlock:^{
        NSData *data = [NSData dataWithContentsOfFile:file];
        if (!data) {
            data = [ZLHTTPStream fetch:url headers:@{ @"Accept": @"image/*" } finalURL:NULL error:NULL];
            if (data.length) [data writeToFile:file atomically:YES];
        } else {
            // A touch, so that the trim of the disk keeps images in use.
            [[NSFileManager defaultManager] setAttributes:@{ NSFileModificationDate: [NSDate date] } ofItemAtPath:file error:NULL];
        }
        UIImage *image = data ? ZLDecode(data, pixels, scale) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (image) {
                NSUInteger cost = (NSUInteger)(image.size.width * image.size.height * scale * scale * 4);
                [self.images setObject:image forKey:key cost:cost];
            }
            NSArray *waiting = self.waiting[key];
            [self.waiting removeObjectForKey:key];
            for (void (^each)(UIImage *) in waiting) each(image);
        });
    }];
}

- (void)trimDisk {
    NSString *folder = self.folder;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSFileManager *files = [NSFileManager defaultManager];
        NSArray *keys = @[ NSURLContentModificationDateKey, NSURLFileSizeKey ];
        NSArray *items = [files contentsOfDirectoryAtURL:[NSURL fileURLWithPath:folder] includingPropertiesForKeys:keys
                                                 options:0 error:NULL];
        unsigned long long total = 0;
        NSMutableArray *entries = [NSMutableArray array];
        for (NSURL *item in items) {
            NSDictionary *values = [item resourceValuesForKeys:keys error:NULL];
            total += [values[NSURLFileSizeKey] unsignedLongLongValue];
            [entries addObject:@[ values[NSURLContentModificationDateKey] ?: [NSDate distantPast], item, values[NSURLFileSizeKey] ?: @0 ]];
        }
        if (total <= ZLDiskLimit) return;
        [entries sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [a[0] compare:b[0]]; }];
        for (NSArray *entry in entries) {
            if (total <= ZLDiskLimit * 3 / 4) break;
            [files removeItemAtURL:entry[1] error:NULL];
            total -= [entry[2] unsignedLongLongValue];
        }
    });
}

- (void)clearDisk {
    [[NSFileManager defaultManager] removeItemAtPath:self.folder error:NULL];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.folder withIntermediateDirectories:YES attributes:nil error:NULL];
    [self.images removeAllObjects];
}

@end
