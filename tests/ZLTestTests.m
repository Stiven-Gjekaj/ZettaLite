// Tests of the test runner itself.

#import "ZLTest.h"

ZL_TEST(test_runner_compares_equal_objects) {
    ZL_EQUAL(([NSString stringWithFormat:@"%d", 42]), @"42");
    ZL_EQUAL_INT(6 * 7, 42);
    ZL_EXPECT(YES);
}
