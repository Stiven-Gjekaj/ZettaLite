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
ls -l "$OUT"
