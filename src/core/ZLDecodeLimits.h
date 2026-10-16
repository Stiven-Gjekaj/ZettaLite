// The speed of the software decoders on the A5 chip, as measured on the
// iPhone 4S with probe/bench.m (2026-10-17). A stream that needs more than
// the decoder can give is "too heavy".

#import <Foundation/Foundation.h>

// The pixels per second that the decoder gives on 2 threads, or 0 when the
// app does not know the codec. codec is an FFmpeg name, for example "hevc".
double ZLSoftwareDecodeCapacity(NSString *codec, int bitDepth);

// YES when the own player can decode the stream in real time, with a margin
// for the display and the sound. A frame rate of 0 counts as 30.
BOOL ZLSoftwareDecodeFits(NSString *codec, int bitDepth, int width, int height, double fps);
