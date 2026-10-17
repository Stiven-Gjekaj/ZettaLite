#import "ZLTest.h"
#import "ZLAddon.h"
#import "ZLLink.h"
#import "ZLMeta.h"

static ZLAddon *Cinemeta(void) {
    NSDictionary *manifest = @{
        @"id": @"com.linvo.cinemeta",
        @"name": @"Cinemeta",
        @"version": @"3.0.0",
        @"types": @[ @"movie", @"series" ],
        @"idPrefixes": @[ @"tt" ],
        @"resources": @[ @"catalog", @{ @"name": @"meta", @"types": @[ @"movie", @"series" ], @"idPrefixes": @[ @"tt" ] } ],
        @"catalogs": @[
            @{ @"type": @"movie", @"id": @"top", @"name": @"Popular",
               @"extra": @[ @{ @"name": @"genre", @"options": @[ @"Action", @"Drama" ] }, @{ @"name": @"skip" } ] },
            @{ @"type": @"movie", @"id": @"top", @"name": @"Search", @"extra": @[ @{ @"name": @"search", @"isRequired": @YES } ] },
            @{ @"type": @"series", @"id": @"year", @"extraSupported": @[ @"genre" ], @"extraRequired": @[ @"genre" ] },
            @{ @"name": @"No type" },
        ],
    };
    return [ZLAddon addonWithManifest:manifest URL:[NSURL URLWithString:@"https://v3-cinemeta.strem.io/manifest.json"]];
}

ZL_TEST(test_addon_reads_the_manifest) {
    ZLAddon *addon = Cinemeta();
    ZL_EQUAL(addon.name, @"Cinemeta");
    ZL_EQUAL(addon.baseURL.absoluteString, @"https://v3-cinemeta.strem.io/");
    ZL_EQUAL_INT(addon.catalogs.count, 3);
    ZLCatalog *popular = addon.catalogs[0];
    ZL_EXPECT(!popular.needsExtra);
    ZL_EXPECT(!popular.supportsSearch);
    ZL_EQUAL([popular extraNamed:@"genre"].options, (@[ @"Action", @"Drama" ]));
    ZLCatalog *search = addon.catalogs[1];
    ZL_EXPECT(search.supportsSearch);
    ZL_EXPECT(search.needsExtra);
    // The old form of the extras.
    ZL_EXPECT([addon.catalogs[2] needsExtra]);
}

ZL_TEST(test_addon_makes_the_urls_of_the_protocol) {
    ZLAddon *addon = Cinemeta();
    ZLCatalog *popular = addon.catalogs[0];
    ZL_EQUAL([popular URLWithExtras:nil].absoluteString, @"https://v3-cinemeta.strem.io/catalog/movie/top.json");
    ZL_EQUAL([popular URLWithExtras:(@{ @"skip": @"100", @"genre": @"Sci-Fi & Fantasy" })].absoluteString,
             @"https://v3-cinemeta.strem.io/catalog/movie/top/genre=Sci-Fi%20%26%20Fantasy&skip=100.json");
    ZL_EQUAL([addon URLForResource:@"stream" type:@"series" identifier:@"tt0944947:1:2"].absoluteString,
             @"https://v3-cinemeta.strem.io/stream/series/tt0944947:1:2.json");
}

ZL_TEST(test_addon_keeps_the_query_of_a_configured_addon) {
    ZLAddon *addon = [ZLAddon addonWithManifest:@{ @"id": @"x" }
                                            URL:ZLMediaURLFromText(@"https://example.org/key=abc|lang=en/manifest.json")];
    ZL_EQUAL([addon URLForResource:@"meta" type:@"movie" identifier:@"tt1"].absoluteString,
             @"https://example.org/key=abc%7Clang=en/meta/movie/tt1.json");
}

ZL_TEST(test_addon_knows_which_resources_it_gives) {
    ZLAddon *addon = Cinemeta();
    ZL_EXPECT([addon supportsResource:@"meta" type:@"movie" identifier:@"tt0111161"]);
    ZL_EXPECT(![addon supportsResource:@"meta" type:@"movie" identifier:@"kitsu:1"]);
    ZL_EXPECT(![addon supportsResource:@"meta" type:@"tv" identifier:@"tt1"]);
    ZL_EXPECT(![addon supportsResource:@"stream" type:@"movie" identifier:@"tt1"]);
    ZL_EXPECT([addon supportsResource:@"catalog" type:@"series" identifier:nil]);
}

ZL_TEST(test_meta_reads_a_series_with_episodes) {
    NSDictionary *json = @{
        @"id": @"tt0944947", @"type": @"series", @"name": @"Game of Thrones", @"releaseInfo": @"2011-2019",
        @"imdbRating": @"9.2", @"runtime": @"57 min", @"genres": @[ @"Drama" ],
        @"links": @[ @{ @"name": @"Emilia Clarke", @"category": @"Cast" }, @{ @"name": @"Fantasy", @"category": @"Genres" } ],
        @"videos": @[
            @{ @"id": @"tt0944947:2:1", @"title": @"The North Remembers", @"season": @2, @"episode": @1, @"released": @"2012-04-01T00:00:00.000Z" },
            @{ @"id": @"tt0944947:0:1", @"title": @"Extra", @"season": @0, @"episode": @1 },
            @{ @"id": @"tt0944947:1:2", @"name": @"The Kingsroad", @"season": @"1", @"number": @2 },
            @{ @"id": @"tt0944947:1:1", @"title": @"Winter Is Coming", @"season": @1, @"episode": @1 },
        ],
    };
    ZLMeta *meta = [ZLMeta metaWithJSON:json];
    ZL_EQUAL(meta.name, @"Game of Thrones");
    ZL_EQUAL(meta.genres, (@[ @"Drama", @"Fantasy" ]));
    ZL_EQUAL(meta.cast, (@[ @"Emilia Clarke" ]));
    ZL_EQUAL(meta.seasons, (@[ @1, @2, @0 ]));
    NSArray *first = [meta episodesOfSeason:1];
    ZL_EQUAL_INT(first.count, 2);
    ZL_EQUAL([first[0] title], @"Winter Is Coming");
    ZL_EQUAL([first[1] title], @"The Kingsroad");
    ZL_EQUAL([(ZLEpisode *)first[1] code], @"S1 E2");
    ZL_EXPECT([[meta.episodes.lastObject released] timeIntervalSince1970] > 1333000000);
    ZL_EQUAL(meta.facts, @"2011-2019  |  57 min  |  IMDb 9.2");
}

ZL_TEST(test_stream_reads_http_and_torrent_streams) {
    ZLStream *http = [ZLStream streamWithJSON:@{
        @"url": @"https://cdn.example.org/a b.mkv", @"name": @"RD+\n1080p", @"title": @"Film.2020.1080p.x264.mkv",
        @"behaviorHints": @{ @"proxyHeaders": @{ @"request": @{ @"Referer": @"https://example.org/" } }, @"videoSize": @123456789 },
    }];
    ZL_EQUAL(http.URL.absoluteString, @"https://cdn.example.org/a%20b.mkv");
    ZL_EXPECT(!http.isTorrent);
    ZL_EQUAL(http.headers, (@{ @"Referer": @"https://example.org/" }));
    ZL_EQUAL_INT(http.size, 123456789);
    ZLStream *torrent = [ZLStream streamWithJSON:@{ @"infoHash": @"abc", @"fileIdx": @1, @"title": @"x" }];
    ZL_EXPECT(torrent.isTorrent);
    ZL_EXPECT([ZLStream streamWithJSON:@{ @"title": @"nothing" }] == nil);
}
