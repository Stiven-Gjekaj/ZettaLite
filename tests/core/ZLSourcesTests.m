#import "ZLTest.h"
#import "ZLSources.h"
#import "ZLStore.h"

ZL_TEST(test_sources_read_a_pasted_list) {
    NSString *text = @"https://v3-cinemeta.strem.io/manifest.json\n"
                     @"\n# a comment\n"
                     @"  stremio://torrentio.strem.fun/realdebrid=KEY/manifest.json  \r\n"
                     @"http://example.org/live.m3u\n"
                     @"http://example.org/get.php?username=a&password=b&type=m3u_plus\n"
                     @"https://example.org/guide.xml.gz\n"
                     @"https://example.org/film.mkv\n"
                     @"not a link\n"
                     @"https://v3-cinemeta.strem.io/manifest.json\n";
    NSArray *sources = ZLParseSources(text);
    ZL_EQUAL_INT(sources.count, 6);
    ZL_EQUAL_INT(((ZLSource *)sources[0]).kind, ZLSourceAddon);
    ZL_EQUAL(((ZLSource *)sources[1]).URL.absoluteString, @"https://torrentio.strem.fun/realdebrid=KEY/manifest.json");
    ZL_EQUAL_INT(((ZLSource *)sources[1]).kind, ZLSourceAddon);
    ZL_EQUAL_INT(((ZLSource *)sources[2]).kind, ZLSourcePlaylist);
    ZL_EQUAL_INT(((ZLSource *)sources[3]).kind, ZLSourcePlaylist);
    ZL_EQUAL_INT(((ZLSource *)sources[4]).kind, ZLSourceGuide);
    ZL_EQUAL_INT(((ZLSource *)sources[5]).kind, ZLSourceLink);
}

ZL_TEST(test_store_keeps_values_on_the_disk) {
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
    ZLStore *store = [[ZLStore alloc] initWithDirectory:directory];
    NSMutableArray *list = [NSMutableArray arrayWithObject:@"a"];
    [store setObject:list named:@"list"];
    [list addObject:@"b"];
    ZL_EQUAL([store objectNamed:@"list"], (@[ @"a" ]));
    [store flush];
    ZLStore *again = [[ZLStore alloc] initWithDirectory:directory];
    ZL_EQUAL([again objectNamed:@"list"], (@[ @"a" ]));
    ZL_EXPECT([again objectNamed:@"none"] == nil);
    [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}
