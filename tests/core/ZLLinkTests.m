#import "ZLTest.h"
#import "ZLLink.h"

ZL_TEST(test_link_reads_a_play_link) {
    ZLLink *link = ZLParseLink([NSURL URLWithString:@"zettalite://play?url=https%3A%2F%2Fexample.org%2Fa%20b.mkv%3Fx%3D1&title=A+film"]);
    ZL_EQUAL(link.mediaURL.absoluteString, @"https://example.org/a%20b.mkv?x=1");
    ZL_EQUAL(link.title, @"A film");
    ZL_EXPECT(link.startTime == 0);
    link = ZLParseLink([NSURL URLWithString:@"zettalite://play?url=http%3A%2F%2Fexample.org%2Fv.mkv&t=95.5"]);
    ZL_EXPECT(link.startTime == 95.5);
}

ZL_TEST(test_link_reads_title_search_and_tab_links) {
    ZLLink *link = ZLParseLink([NSURL URLWithString:@"zettalite://title?type=series&id=tt0944947"]);
    ZL_EQUAL_INT(link.kind, ZLLinkTitle);
    ZL_EQUAL(link.type, @"series");
    ZL_EQUAL(link.identifier, @"tt0944947");
    link = ZLParseLink([NSURL URLWithString:@"zettalite://watch?type=series&id=tt0944947%3A1%3A2"]);
    ZL_EQUAL_INT(link.kind, ZLLinkWatch);
    ZL_EQUAL(link.identifier, @"tt0944947:1:2");
    link = ZLParseLink([NSURL URLWithString:@"zettalite://search?q=the%20matrix"]);
    ZL_EQUAL_INT(link.kind, ZLLinkSearch);
    ZL_EQUAL(link.text, @"the matrix");
    link = ZLParseLink([NSURL URLWithString:@"zettalite://tab?name=live"]);
    ZL_EQUAL_INT(link.kind, ZLLinkTab);
    ZL_EXPECT(ZLParseLink([NSURL URLWithString:@"zettalite://tab?name=other"]) == nil);
    ZL_EXPECT(ZLParseLink([NSURL URLWithString:@"zettalite://title?type=movie"]) == nil);
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
