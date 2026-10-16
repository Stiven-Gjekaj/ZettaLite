#import "ZLTest.h"
#import "ZLStreamInfo.h"

ZL_TEST(test_stream_info_reads_a_release_name) {
    ZLStreamInfo *info = [ZLStreamInfo infoForText:@"RD+\n1080p\nFilm.2020.1080p.BluRay.x265.10bit.DTS-HD.MA.5.1-GROUP\n4.52 GB"];
    ZL_EQUAL_INT(info.height, 1080);
    ZL_EQUAL_INT(info.codec, ZLVideoCodecHEVC);
    ZL_EXPECT(info.tenBit);
    ZL_EQUAL(info.audio, @"DTS-HD");
    ZL_EXPECT(fabs(info.gigabytes - 4.52) < 0.001);
    ZL_EXPECT(![info hardwareDecodes]);
    // 10-bit HEVC at 1080p is far above the measured limit.
    ZL_EXPECT([info tooHeavy]);
    ZL_EQUAL(info.badges, (@[ @"1080p", @"HEVC", @"10-bit", @"DTS-HD", @"4.5 GB", @"Too heavy" ]));
    ZL_EXPECT(info.score == 0);
}

ZL_TEST(test_stream_info_prefers_h264_in_hardware) {
    ZLStreamInfo *h264 = [ZLStreamInfo infoForText:@"Film.2020.1080p.WEB-DL.DD5.1.H.264"];
    ZL_EXPECT([h264 hardwareDecodes]);
    ZL_EQUAL(h264.audio, @"AC3");
    ZLStreamInfo *hevc = [ZLStreamInfo infoForText:@"Film.2020.480p.WEB.x265"];
    ZL_EXPECT(![hevc tooHeavy]);
    ZL_EXPECT([hevc.badges containsObject:@"Software"]);
    ZLStreamInfo *small = [ZLStreamInfo infoForText:@"Film.2020.720p.x264"];
    ZLStreamInfo *uhd = [ZLStreamInfo infoForText:@"Film 2160p HDR DV x265"];
    ZL_EXPECT(h264.score > small.score);
    ZL_EXPECT(small.score > hevc.score);
    ZL_EXPECT(uhd.score == 0);
    ZL_EQUAL(uhd.qualityText, @"4K");
    ZL_EXPECT(uhd.dolbyVision);
}

ZL_TEST(test_stream_info_does_not_read_words_inside_words) {
    // "hd" in "hdtv" and "ts" in "parts" are not quality words.
    ZLStreamInfo *info = [ZLStreamInfo infoForText:@"Show.S01E02.HDTV.Parts"];
    ZL_EQUAL_INT(info.height, 0);
    ZL_EXPECT(!info.camera);
    ZLStreamInfo *camera = [ZLStreamInfo infoForText:@"Film.2024.HDCAM.x264"];
    ZL_EXPECT(camera.camera);
    ZL_EXPECT(camera.score < [ZLStreamInfo infoForText:@"Film.2024.x264"].score);
}
