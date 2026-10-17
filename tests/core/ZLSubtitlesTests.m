#import "ZLTest.h"
#import "ZLSubtitles.h"

ZL_TEST(test_subtitles_read_srt) {
    NSString *srt = @"﻿1\r\n00:00:01,000 --> 00:00:02,500\r\n<i>Hello</i>\r\nworld\r\n\r\n"
                    @"2\r\n00:00:03,000 --> 00:00:04,000\r\n{\\an8}Top &amp; more\r\n"
                    @"3\r\n00:01:05,250 --> 00:01:06,000\r\nNo empty line before\r\n\r\n"
                    @"4\r\n00:00:09,000 --> 00:00:08,000\r\nBad times\r\n";
    NSArray *cues = ZLParseSubtitles(srt);
    ZL_EQUAL_INT(cues.count, 3);
    ZLCue *first = cues[0];
    ZL_EXPECT(first.start == 1.0 && first.end == 2.5);
    ZL_EQUAL(first.text, @"Hello\nworld");
    ZL_EQUAL([cues[1] text], @"Top & more");
    ZL_EXPECT(((ZLCue *)cues[2]).start == 65.25);
    ZL_EQUAL([cues[2] text], @"No empty line before");
}

ZL_TEST(test_subtitles_read_vtt) {
    NSString *vtt = @"WEBVTT\n\nNOTE a comment\n\nintro\n00:01.000 --> 00:02.000 align:start position:10%\n<c.yellow>One</c>\n\n"
                    @"01:00:00.000 --> 01:00:01.000\n<v Anna>Two\n";
    NSArray *cues = ZLParseSubtitles(vtt);
    ZL_EQUAL_INT(cues.count, 2);
    ZL_EQUAL([cues[0] text], @"One");
    ZL_EXPECT(((ZLCue *)cues[0]).end == 2.0);
    ZL_EXPECT(((ZLCue *)cues[1]).start == 3600.0);
    ZL_EQUAL([cues[1] text], @"Two");
}

ZL_TEST(test_subtitles_decode_bytes) {
    const uint8_t latin[] = { 'C', 'a', 'f', 0xE9 };
    ZL_EQUAL(ZLSubtitleText([NSData dataWithBytes:latin length:4]), @"Café");
    ZL_EQUAL(ZLSubtitleText([@"﻿Café" dataUsingEncoding:NSUTF8StringEncoding]), @"Café");
    ZL_EQUAL(ZLSubtitleText([@"Hi" dataUsingEncoding:NSUnicodeStringEncoding]), @"Hi");
}

ZL_TEST(test_subtitles_read_ass_packets) {
    ZL_EQUAL(ZLASSPacketText(@"12,0,Default,,0,0,0,,{\\i1}Hello,{\\i0} there\\Nfriend"), @"Hello, there\nfriend");
}

ZL_TEST(test_subtitles_find_the_cue_of_a_time) {
    ZLCueList *list = [[ZLCueList alloc] initWithCues:@[ [ZLCue cueWithStart:1 end:3 text:@"a"] ]];
    [list addCue:[ZLCue cueWithStart:10 end:12 text:@"c"]];
    [list addCue:[ZLCue cueWithStart:2 end:4 text:@"b"]];
    [list addCue:[ZLCue cueWithStart:2 end:4 text:@"b"]];
    ZL_EQUAL_INT([list count], 3);
    ZL_EXPECT([list textAt:0.5] == nil);
    ZL_EQUAL([list textAt:1.5], @"a");
    ZL_EQUAL([list textAt:2.5], @"a\nb");
    ZL_EQUAL([list textAt:3.5], @"b");
    ZL_EXPECT([list textAt:5] == nil);
    ZL_EQUAL([list textAt:11], @"c");
}
