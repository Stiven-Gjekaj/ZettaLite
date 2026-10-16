#import "ZLTest.h"
#import "ZLLibrary.h"
#import "ZLStore.h"

static ZLStore *TemporaryStore(void) {
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
    return [[ZLStore alloc] initWithDirectory:directory];
}

static NSString *Day(NSInteger offset) {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"yyyy-MM-dd";
    formatter.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSinceNow:offset * 86400.0]];
}

static ZLMeta *Series(void) {
    return [ZLMeta metaWithJSON:@{ @"id": @"tt1", @"type": @"series", @"name": @"Show", @"videos": @[
        @{ @"id": @"tt1:1:1", @"season": @1, @"episode": @1, @"released": Day(-60) },
        @{ @"id": @"tt1:1:2", @"season": @1, @"episode": @2, @"released": Day(-53) },
        @{ @"id": @"tt1:1:3", @"season": @1, @"episode": @3, @"released": Day(-3) },
        @{ @"id": @"tt1:1:4", @"season": @1, @"episode": @4, @"released": Day(4) },
        @{ @"id": @"tt1:0:1", @"season": @0, @"episode": @1, @"released": Day(-1) },
    ] }];
}

ZL_TEST(test_library_keeps_the_watchlist_and_the_progress) {
    ZLStore *store = TemporaryStore();
    ZLLibrary *library = [[ZLLibrary alloc] initWithStoreName:@"library" store:store];
    ZLMeta *film = [ZLMeta metaWithJSON:@{ @"id": @"tt9", @"type": @"movie", @"name": @"Film" }];
    [library setMeta:film inWatchlist:YES];
    ZL_EXPECT([library isInWatchlist:@"tt9"]);
    [library recordMeta:film video:@"tt9" position:1200 duration:6000];
    ZL_EXPECT(![library isWatched:@"tt9"]);
    ZL_EXPECT(fabs([library progressOf:@"tt9"] - 0.2) < 0.001);
    ZL_EQUAL_INT([library continueWatching].count, 1);
    // 90% counts as watched, and the film leaves continue watching.
    [library recordMeta:film video:@"tt9" position:5500 duration:6000];
    ZL_EXPECT([library isWatched:@"tt9"]);
    ZL_EQUAL_INT([library continueWatching].count, 0);
    ZL_EQUAL_INT([library watchlist].count, 1);
    // The library stays after a restart.
    [store flush];
    ZLLibrary *again = [[ZLLibrary alloc] initWithStoreName:@"library" store:[[ZLStore alloc] initWithDirectory:store.directory]];
    ZL_EXPECT([again isWatched:@"tt9"]);
    ZL_EXPECT([again isInWatchlist:@"tt9"]);
    [[NSFileManager defaultManager] removeItemAtPath:store.directory error:NULL];
}

ZL_TEST(test_library_finds_the_next_episode) {
    ZLLibrary *library = [[ZLLibrary alloc] initWithStoreName:@"library" store:TemporaryStore()];
    ZLMeta *show = Series();
    ZL_EQUAL([library nextEpisodeOf:show].identifier, @"tt1:1:1");
    [library setVideo:@"tt1:1:1" ofMeta:show watched:YES];
    ZL_EQUAL([library nextEpisodeOf:show].identifier, @"tt1:1:2");
    // An episode that did not finish comes first.
    [library recordMeta:show video:@"tt1:1:3" position:600 duration:2400];
    ZL_EQUAL([library nextEpisodeOf:show].identifier, @"tt1:1:3");
    [library setVideo:@"tt1:1:2" ofMeta:show watched:YES];
    [library setVideo:@"tt1:1:3" ofMeta:show watched:YES];
    // Episode 4 is not out yet.
    ZL_EXPECT([library nextEpisodeOf:show] == nil);
    ZL_EQUAL_INT([library continueWatching].count, 0);
}

ZL_TEST(test_library_keeps_the_episodes_of_a_newer_copy) {
    ZLLibrary *library = [[ZLLibrary alloc] initWithStoreName:@"library" store:TemporaryStore()];
    ZLMeta *small = [ZLMeta metaWithJSON:@{ @"id": @"tt1", @"type": @"series", @"name": @"Show" }];
    [library setVideo:@"tt1:1:1" ofMeta:small watched:YES];
    ZL_EXPECT([library nextEpisodeOf:[library itemFor:@"tt1"].meta] == nil);
    [library updateMeta:Series()];
    ZL_EQUAL([library nextEpisodeOf:[library itemFor:@"tt1"].meta].identifier, @"tt1:1:2");
    // A title that is not in the library stays out.
    [library updateMeta:[ZLMeta metaWithJSON:@{ @"id": @"tt2", @"type": @"movie", @"name": @"Other" }]];
    ZL_EXPECT([library itemFor:@"tt2"] == nil);
}

ZL_TEST(test_library_finds_new_episodes) {
    ZLLibrary *library = [[ZLLibrary alloc] initWithStoreName:@"library" store:TemporaryStore()];
    NSArray *fresh = [library newEpisodesOf:Series() days:14];
    // Episode 3 and the extra came out in the last 14 days.
    ZL_EQUAL_INT(fresh.count, 2);
    [library setVideo:@"tt1:1:3" ofMeta:Series() watched:YES];
    ZL_EQUAL_INT([library newEpisodesOf:Series() days:14].count, 1);
}

ZL_TEST(test_library_restores_a_backup) {
    ZLLibrary *library = [[ZLLibrary alloc] initWithStoreName:@"library" store:TemporaryStore()];
    [library setMeta:Series() inWatchlist:YES];
    NSDictionary *backup = [library backup];
    ZLLibrary *other = [[ZLLibrary alloc] initWithStoreName:@"library" store:TemporaryStore()];
    ZL_EXPECT([other restore:backup]);
    ZL_EXPECT([other isInWatchlist:@"tt1"]);
    ZL_EXPECT(![other restore:@{ @"x": @1 }]);
}
