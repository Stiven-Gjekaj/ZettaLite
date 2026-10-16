#import "ZLTest.h"
#import "ZLM3U.h"

ZL_TEST(test_m3u_reads_channels_with_attributes_and_headers) {
    NSString *text = @"#EXTM3U url-tvg=\"http://example.org/guide.xml\"\n"
                     @"#EXTINF:-1 tvg-id=\"news.1\" tvg-name=\"News One\" tvg-logo=\"http://example.org/n1.png\" group-title=\"News, World\",News One HD\n"
                     @"#EXTVLCOPT:http-user-agent=Player/1.0\n"
                     @"#EXTVLCOPT:http-referrer=http://example.org/\n"
                     @"http://example.org/live/news1.ts\n"
                     @"\n"
                     @"#EXTINF:0,Music\n"
                     @"#EXTGRP:Music\n"
                     @"music/index.m3u8|User-Agent=Kodi%2F20&Referer=http://m.example.org/\n"
                     @"#EXTINF:-1 group-title=\"Sport\",Sport\n"
                     @"#EXTHTTP:{\"Cookie\":\"a=1\"}\n"
                     @"https://example.org/sport.m3u8\n"
                     @"#EXTINF:-1,Bad\n"
                     @"rtmp://example.org/live\n";
    NSArray *channels = ZLParseM3U(text, [NSURL URLWithString:@"http://example.org/list/all.m3u"]);
    ZL_EQUAL_INT(channels.count, 3);
    ZLChannel *news = channels[0];
    ZL_EQUAL(news.name, @"News One HD");
    ZL_EQUAL(news.group, @"News, World");
    ZL_EQUAL(news.tvgID, @"news.1");
    ZL_EQUAL(news.logo.absoluteString, @"http://example.org/n1.png");
    ZL_EQUAL(news.headers, (@{ @"User-Agent": @"Player/1.0", @"Referer": @"http://example.org/" }));
    ZLChannel *music = channels[1];
    ZL_EQUAL(music.URL.absoluteString, @"http://example.org/list/music/index.m3u8");
    ZL_EQUAL(music.group, @"Music");
    ZL_EQUAL(music.headers, (@{ @"User-Agent": @"Kodi/20", @"Referer": @"http://m.example.org/" }));
    ZL_EQUAL([channels[2] headers], (@{ @"Cookie": @"a=1" }));
}

ZL_TEST(test_m3u_knows_an_hls_stream) {
    NSString *hls = @"#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:6\n#EXTINF:6.0,\nseg0.ts\n";
    ZL_EXPECT(ZLIsHLSPlaylist(hls));
    ZL_EQUAL_INT(ZLParseM3U(hls, nil).count, 0);
    ZL_EXPECT(!ZLIsHLSPlaylist(@"#EXTM3U\n#EXTINF:-1,One\nhttp://a/1\n"));
}
