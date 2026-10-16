#import "ZLTest.h"
#import "ZLSettings.h"

ZL_TEST(test_language_codes_become_three_letters) {
    ZL_EQUAL(ZLLanguage3(@"en"), @"eng");
    ZL_EQUAL(ZLLanguage3(@"de-AT"), @"ger");
    ZL_EQUAL(ZLLanguage3(@"SQ"), @"alb");
    ZL_EQUAL(ZLLanguage3(@"ita"), @"ita");
    ZL_EXPECT(ZLLanguage3(@"x") == nil);
}
