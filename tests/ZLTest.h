// ZLTest: a small test runner that operates on macOS and on iOS 6.
// Each test is a function that ZL_TEST makes and registers at load time.

#import <Foundation/Foundation.h>

typedef void (*ZLTestFunction)(void);

void ZLTestRegister(const char *name, ZLTestFunction function);
void ZLTestFail(const char *file, int line, NSString *message);
void ZLTestSkip(void);

#define ZL_TEST(name)                                                         \
    static void name(void);                                                   \
    __attribute__((constructor)) static void name##_register(void) {          \
        ZLTestRegister(#name, name);                                          \
    }                                                                         \
    static void name(void)

#define ZL_EXPECT(condition)                                                  \
    do {                                                                      \
        if (!(condition)) ZLTestFail(__FILE__, __LINE__, @"expected: " #condition); \
    } while (0)

#define ZL_EQUAL(actual, expected)                                            \
    do {                                                                      \
        id zl_a = (actual), zl_e = (expected);                                \
        if (!(zl_a == zl_e || [zl_a isEqual:zl_e]))                           \
            ZLTestFail(__FILE__, __LINE__, [NSString stringWithFormat:        \
                @"%s is <%@>, expected <%@>", #actual, zl_a, zl_e]);           \
    } while (0)

#define ZL_EQUAL_INT(actual, expected)                                        \
    do {                                                                      \
        long long zl_a = (long long)(actual), zl_e = (long long)(expected);   \
        if (zl_a != zl_e)                                                     \
            ZLTestFail(__FILE__, __LINE__, [NSString stringWithFormat:        \
                @"%s is %lld, expected %lld", #actual, zl_a, zl_e]);           \
    } while (0)

// A live test uses the network. It runs only when ZL_LIVE=1 is set.
#define ZL_LIVE_ONLY()                                                        \
    do {                                                                      \
        const char *zl_live = getenv("ZL_LIVE");                              \
        if (!zl_live || !*zl_live) {                                          \
            ZLTestSkip();                                                     \
            return;                                                           \
        }                                                                     \
    } while (0)

// Runs the run loop until done is YES or the time is over.
BOOL ZLTestWait(BOOL *done, NSTimeInterval seconds);
