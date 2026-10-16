// Runs each registered test and prints one line for each failure.
// The exit status is 0 when all tests pass.

#import "ZLTest.h"

#define ZL_MAX_TESTS 512

static const char *gNames[ZL_MAX_TESTS];
static ZLTestFunction gFunctions[ZL_MAX_TESTS];
static int gCount;
static int gFailures;
static int gSkipped;
static const char *gCurrent;

void ZLTestRegister(const char *name, ZLTestFunction function) {
    if (gCount < ZL_MAX_TESTS) {
        gNames[gCount] = name;
        gFunctions[gCount] = function;
        gCount++;
    }
}

void ZLTestFail(const char *file, int line, NSString *message) {
    gFailures++;
    const char *base = strrchr(file, '/');
    printf("FAIL %s (%s:%d): %s\n", gCurrent, base ? base + 1 : file, line, message.UTF8String);
}

void ZLTestSkip(void) {
    gSkipped++;
}

BOOL ZLTestWait(BOOL *done, NSTimeInterval seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!*done && [until timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    return *done;
}

int main(int argc, char **argv) {
    int failedTests = 0;
    for (int i = 0; i < gCount; i++) {
        if (argc > 1 && !strstr(gNames[i], argv[1])) continue;
        @autoreleasepool {
            int before = gFailures;
            gCurrent = gNames[i];
            gFunctions[i]();
            if (gFailures != before) failedTests++;
        }
    }
    printf("%d tests, %d failed, %d skipped\n", gCount, failedTests, gSkipped);
    return failedTests == 0 ? 0 : 1;
}
