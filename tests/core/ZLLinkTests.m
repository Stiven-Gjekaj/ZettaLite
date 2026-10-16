#import "ZLTest.h"
#import "ZLLink.h"

ZL_TEST(test_link_reads_a_play_link) {
    ZLLink *link = ZLParseLink([NSURL URLWithString:@"zettalite://play?url=https%3A%2F%2Fexample.org%2Fa%20b.mkv%3Fx%3D1&title=A+film"]);
    ZL_EQUAL(link.mediaURL.absoluteString, @"https://example.org/a%20b.mkv?x=1");
    ZL_EQUAL(link.title, @"A film");
}

ZL_TEST(test_link_refuses_other_links) {
    ZL_EXPECT(ZLParseLink([NSURL URLWithString:@"zettalite://play?url=ftp%3A%2F%2Fexample.org%2Fa"]) == nil);
    ZL_EXPECT(ZLParseLink([NSURL URLWithString:@"zettalite://other?url=http%3A%2F%2Fexample.org"]) == nil);
    ZL_EXPECT(ZLParseLink([NSURL URLWithString:@"http://example.org/"]) == nil);
}

ZL_TEST(test_pasted_text_becomes_a_url) {
    ZL_EQUAL(ZLMediaURLFromText(@"  http://example.org/v.mp4\n").absoluteString, @"http://example.org/v.mp4");
    ZL_EQUAL(ZLMediaURLFromText(@"http://example.org/my file.mkv").absoluteString, @"http://example.org/my%20file.mkv");
    ZL_EXPECT(ZLMediaURLFromText(@"example.org/v.mp4") == nil);
    ZL_EXPECT(ZLMediaURLFromText(@"") == nil);
}
