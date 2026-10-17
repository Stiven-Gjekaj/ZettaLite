#!/bin/sh
# Make the small media files that the media tests play, into build/fixtures/.
# They come from the test sources of FFmpeg, so git holds no media files.
# Usage: scripts/fixtures.sh
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/fixtures"
mkdir -p "$OUT"
cd "$OUT"
F="ffmpeg -hide_banner -loglevel error -y"
V="-f lavfi -i testsrc2=size=320x240:rate=25:duration=24"
A="-f lavfi -i sine=frequency=440:sample_rate=48000:duration=24"
# A keyframe each 2 seconds, as in most streams.
G="-g 50 -keyint_min 50 -sc_threshold 0"

$F $V $A $G -c:v libx264 -profile:v main -c:a aac -ac 2 -movflags +faststart h264-aac.mp4
$F $V $A $G -c:v libx264 -c:a ac3 -ac 2 h264-ac3.mkv
$F $V $A $G -c:v libx264 -c:a aac -ac 2 -f mpegts h264-aac.ts
$F $V $A $G -c:v libx264 -c:a libopus -ac 2 h264-opus.mkv
$F $V $A $G -c:v libx265 -x265-params log-level=error -c:a aac -ac 2 hevc-aac.mkv
$F $V $A $G -c:v libvpx-vp9 -b:v 300k -c:a libopus vp9-opus.webm
$F $A -c:a flac audio.flac
# DASH with separate video and audio, as a streaming site sends it.
mkdir -p dash
$F $V $A $G -c:v libx264 -c:a aac -ac 2 -map 0:v -map 1:a -seg_duration 4 -use_template 1 -use_timeline 0 \
    -f dash dash/manifest.mpd
# HLS and an M3U list of channels, as an IPTV service gives them.
mkdir -p live
$F $V $A $G -c:v libx264 -profile:v main -c:a aac -ac 2 -hls_time 4 -hls_list_size 0 \
    -f hls live/index.m3u8
cat >live/tv.m3u <<M3U
#EXTM3U
#EXTINF:-1 tvg-id="test.hls" tvg-logo="http://127.0.0.1:8765/live/logo.png" group-title="Test",Test HLS
index.m3u8
#EXTINF:-1 group-title="Test",Test TS
#EXTVLCOPT:http-user-agent=ZettaLite-Test
../h264-aac.ts
#EXTINF:-1 group-title="Other tests",Test HEVC
../hevc-aac.mkv
M3U
cp "$ROOT/resources/Icon@2x.png" live/logo.png
# Text subtitles inside a file: SubRip and ASS in Matroska, mov_text in MP4.
cat >subs.srt <<SRT
1
00:00:01,000 --> 00:00:03,000
<i>First line</i>

2
00:00:10,000 --> 00:00:12,500
Second line
with two rows
SRT
$F -i h264-aac.mp4 -i subs.srt -map 0 -map 1 -c copy -c:s srt -metadata:s:s:0 language=eng subs-srt.mkv
$F -i h264-aac.mp4 -i subs.srt -map 0 -map 1 -c copy -c:s ass subs-ass.mkv
$F -i h264-aac.mp4 -i subs.srt -map 0 -map 1 -c copy -c:s mov_text subs-text.mp4
$F -i hevc-aac.mkv -i subs.srt -map 0 -map 1 -c copy -c:s srt -metadata:s:s:0 language=eng subs-hevc.mkv
# A long file, for the progress of the library.
L="-f lavfi -i testsrc2=size=320x240:rate=25:duration=180 -f lavfi -i sine=frequency=440:sample_rate=48000:duration=180"
$F $L $G -c:v libx264 -c:a aac -ac 2 -movflags +faststart h264-long.mp4
# A French copy of the subtitles, for the picker.
sed 's/First line/Premiere ligne/; s/Second line/Deuxieme ligne/; s/with two rows/sur deux rangs/' subs.srt >subs-fr.srt

# A Stremio addon for the checks of the app on the phone. scripts/test.sh
# does not use it. Serve build/fixtures on port 8765 and add
# http://127.0.0.1:8765/addon/manifest.json in Sources.
U=http://127.0.0.1:8765
POSTER="$U/addon/poster.jpg"
mkdir -p addon/catalog/movie addon/catalog/series addon/meta/movie addon/meta/series \
    addon/stream/movie addon/stream/series addon/subtitles/series
$F -f lavfi -i testsrc2=size=300x450 -frames:v 1 addon/poster.jpg
cat >addon/manifest.json <<JSON
{"id": "zl.test", "version": "1.0.0", "name": "ZL Test", "types": ["movie", "series"], "idPrefixes": ["zl"], "resources": ["catalog", "meta", "stream", "subtitles"], "catalogs": [{"type": "movie", "id": "films", "name": "Test films"}, {"type": "series", "id": "shows", "name": "Test shows"}]}
JSON
cat >addon/catalog/movie/films.json <<JSON
{"metas": [{"id": "zl1", "type": "movie", "name": "Color Bars", "releaseInfo": "2026", "poster": "$POSTER", "background": "$POSTER"}, {"id": "zl2", "type": "movie", "name": "Opus Test", "releaseInfo": "2026", "poster": "$POSTER"}, {"id": "zl3", "type": "movie", "name": "Three Minutes", "releaseInfo": "2026", "poster": "$POSTER"}]}
JSON
cat >addon/catalog/series/shows.json <<JSON
{"metas": [{"id": "zls", "type": "series", "name": "Test Show", "poster": "$POSTER"}]}
JSON
cat >addon/meta/movie/zl1.json <<JSON
{"meta": {"id": "zl1", "type": "movie", "name": "Color Bars", "releaseInfo": "2026", "poster": "$POSTER", "background": "$POSTER", "description": "A test film.", "genres": ["Test"]}}
JSON
cat >addon/meta/movie/zl2.json <<JSON
{"meta": {"id": "zl2", "type": "movie", "name": "Opus Test", "releaseInfo": "2026", "poster": "$POSTER", "description": "A test film.", "genres": ["Test"]}}
JSON
cat >addon/meta/movie/zl3.json <<JSON
{"meta": {"id": "zl3", "type": "movie", "name": "Three Minutes", "poster": "$POSTER", "description": "A long test."}}
JSON
cat >addon/meta/series/zls.json <<JSON
{"meta": {"id": "zls", "type": "series", "name": "Test Show", "poster": "$POSTER", "videos": [{"id": "zls:1:1", "title": "Pilot", "season": 1, "episode": 1}, {"id": "zls:1:2", "title": "Second", "season": 1, "episode": 2}]}}
JSON
cat >addon/stream/movie/zl1.json <<JSON
{"streams": [{"name": "ZL\n4K", "title": "Film.2160p.HDR.x265.mkv", "url": "$U/hevc-720.mkv"}, {"name": "ZL\n1080p", "title": "Dead.Link.1080p.x264.mkv", "url": "$U/none.mkv"}, {"name": "ZL\n720p", "title": "Color.Bars.720p.x264.AC3.mkv", "url": "$U/h264-ac3.mkv"}, {"name": "ZL\nTorrent", "infoHash": "0123456789abcdef0123456789abcdef01234567"}, {"name": "ZL\n480p", "title": "Color.Bars.480p.x265.mkv", "url": "$U/hevc-aac.mkv"}]}
JSON
cat >addon/stream/movie/zl2.json <<JSON
{"streams": [{"name": "ZL\n240p", "title": "Opus.x264.mkv", "url": "$U/h264-opus.mkv"}]}
JSON
cat >addon/stream/movie/zl3.json <<JSON
{"streams": [{"name": "ZL\n240p", "title": "Long.x264.mp4", "url": "$U/h264-long.mp4"}]}
JSON
cat >addon/stream/series/zls:1:1.json <<JSON
{"streams": [{"name": "ZL\n240p", "title": "Episode.x264.mp4", "url": "$U/h264-aac.mp4"}]}
JSON
# The second episode has a subtitle in the stream, as some addons send it.
cat >addon/stream/series/zls:1:2.json <<JSON
{"streams": [{"name": "ZL\n240p", "title": "Episode.x264.mp4", "url": "$U/h264-aac.mp4", "subtitles": [{"id": "s1", "url": "$U/subs.srt", "lang": "en"}]}]}
JSON
cat >addon/subtitles/series/zls:1:1.json <<JSON
{"subtitles": [{"id": "1", "url": "$U/subs.srt", "lang": "eng"}, {"id": "2", "url": "$U/subs-fr.srt", "lang": "fre"}]}
JSON
cp addon/subtitles/series/zls:1:1.json addon/subtitles/series/zls:1:2.json

# The stamp tells scripts/test.sh which version of this script made the files.
shasum "$ROOT/scripts/fixtures.sh" | cut -d" " -f1 >stamp
ls -l "$OUT"
