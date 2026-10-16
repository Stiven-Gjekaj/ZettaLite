// Reads the sequence parameter set (SPS) of an H.264 stream. The hardware
// decoder of the A5 chip refuses a stream that needs more reference frames
// than level 4.1 permits, so the app must know the count before it picks a
// player.

#import <Foundation/Foundation.h>

typedef struct {
    int profile;
    int level;
    int refs;
    int width;
    int height;
    int bitDepth;
} ZLH264Info;

// Reads the first SPS of avcC data (MP4, MKV) or of Annex B data (TS).
BOOL ZLParseH264Extradata(const uint8_t *data, size_t size, ZLH264Info *info);

// The most reference frames that the hardware decoder accepts at this size.
// It is the limit of level 4.1: 32768 macroblocks in the decoded picture buffer.
int ZLH264HardwareRefLimit(int width, int height);
