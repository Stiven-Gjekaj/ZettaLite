# Architecture

ZettaLite is one iOS app in Objective-C with ARC. It uses the frameworks of
iOS 6, FFmpeg for the media, and mbedTLS for TLS.

## The path of a stream

```
URL -> ZLHTTPStream -> FFmpeg demuxer -> ZLRemuxSession -> ZLHLSServer -> system player
```

1. **HTTP.** `ZLHTTPStream` reads the URL over `ZLConnection`, a TCP socket
   with TLS from mbedTLS. It sends the headers of the source, follows the
   redirects, and reads chunked and gzip bodies. One connection reads ahead
   of the reader. When it is 8 MB ahead, it waits, and TCP stops the server.
   A seek to a far position starts a new connection with a Range header. A
   server that ignores ranges sends the file from the start, and the stream
   drops the bytes before the position.
2. **Demux.** `ZLInput` opens the URL with FFmpeg through a custom AVIO
   context. The HLS and DASH demuxers open their playlists and segments
   through the `io_open` hook of the app, so each byte comes through
   `ZLHTTPStream`.
3. **Route.** `ZLMediaInfo` picks the video and the audio stream, and the
   player. H.264 up to 1080p, 8-bit, with the reference frames that level 4.1
   permits, goes to the system player. Other video goes to the own player.
4. **Remux.** `ZLRemuxSession` cuts the input into MPEG-TS segments of about
   6 seconds. Each segment starts at a video keyframe. FFmpeg copies the
   H.264 video. AAC and MP3 audio stay as they are. Other audio goes through
   `ZLAudioEncoder`, which decodes it, mixes it down to stereo, and encodes
   it to AAC.
5. **HLS server.** `ZLHLSServer` listens on `127.0.0.1`. It gives the
   playlist and the segments of each session.
6. **Player.** `MPMoviePlayerViewController` plays the playlist URL with the
   hardware decoder of the A5 chip.

## The segments

A file that can seek becomes a VOD playlist. The keyframes of the index of
the file (the `stss` of MP4, the cues of Matroska) give the segment times.
A file with no index gets a segment each 6 seconds. Then each segment starts
at the first keyframe at or after its time.

A segment that follows the last segment uses the packets that the last
segment read after its end. So normal playback reads the file one time from
start to end, with no seek. A seek in the player reads the segment at the
new time.

An input that cannot seek, for example a live channel, becomes a live
playlist. One thread cuts the input into segments as they come. The
playlist holds the newest 8 segments.

## The audio grid

`ZLAudioEncoder` puts the AAC frames on one grid of 1024 samples from time
0. Each segment has its own encoder. It also encodes 2 frames before its
start and 2 frames after its end, and then drops them. So the frames of two
segments meet with no gap and no overlap.

## Files

```
src/core/      code with no FFmpeg and no UIKit. The tests run it on the Mac and on the phone.
  ZLConnection   a TCP socket with TLS from mbedTLS
  ZLHTTPStream   an HTTP resource as a stream of bytes with seek
  ZLTrust        the hosts that the user trusts
  ZLHLSServer    the HTTP server on 127.0.0.1
  ZLH264         reads the H.264 SPS
  ZLLink         reads zettalite:// links
  ZLLog          the log file for the diagnostics
src/media/     the code with FFmpeg. The tests run it on the phone.
  ZLInput          opens a URL with FFmpeg
  ZLMediaInfo      picks the streams and the player
  ZLAudioEncoder   changes audio into AAC
  ZLRemuxSession   makes the HLS segments
src/ui/        the screens
src/ffmpeg/    a compiler builtin for FFmpeg that iOS 6 does not have
src/tls/       the configuration of mbedTLS for iOS 6
tests/         the tests
probe/         tools that run on the phone
scripts/       build, test, install, and package
resources/     Info.plist, icons, launch images, root certificates
packaging/     the files of the Cydia package
```

## Third-party code

| Code | Licence | Build |
| --- | --- | --- |
| FFmpeg 7.1.1 | LGPL 2.1 | `scripts/ffmpeg.sh`, one dylib in the app |
| mbedTLS 3.6.2 | Apache 2.0 | `scripts/mbedtls.sh`, linked into the app |
| Mozilla root certificates | MPL 2.0 | `scripts/cacert.sh`, `resources/cacert.pem` |

The scripts download the sources, check the SHA-256, and build them into
`build/`. Git holds none of the third-party sources.

`scripts/ffmpeg.sh` changes three things in FFmpeg:

- The `movrelx` macro of the ARM assembly gets a Darwin local label, so
  that the new Apple linker accepts the objects.
- The DASH demuxer opens each URL through the `io_open` hook, as the HLS
  demuxer does.
- The `https` protocol exists without TLS, so that the HLS and DASH
  demuxers accept https links. The app fetches the bytes itself.
