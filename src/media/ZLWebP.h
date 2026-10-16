// Decodes WebP images with FFmpeg. iOS 6 cannot decode WebP, and some poster
// servers send only WebP, for example images.metahub.space.

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

// YES when the data starts with the header of a WebP file.
BOOL ZLIsWebP(NSData *data);

// Returns an image with its largest side at most pixels, or NULL. The caller
// releases it.
CGImageRef ZLCreateImageFromWebP(NSData *data, CGFloat pixels) CF_RETURNS_RETAINED;
