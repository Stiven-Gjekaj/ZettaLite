// Loads posters and other images. It fetches them through ZLHTTPStream, so
// that hosts with modern TLS work. It makes each image small with ImageIO,
// and it keeps the images in memory and on the disk.

#import <UIKit/UIKit.h>

@interface ZLImageLoader : NSObject

+ (instancetype)shared;

// Returns the image if it is in memory, or nil.
- (UIImage *)cachedImageForURL:(NSURL *)url size:(CGSize)size;

// Loads the image for a view of size points. The handler runs on the main
// queue, also when the load fails.
- (void)loadURL:(NSURL *)url size:(CGSize)size handler:(void (^)(UIImage *image))handler;

// Removes the images on the disk.
- (void)clearDisk;

@end
