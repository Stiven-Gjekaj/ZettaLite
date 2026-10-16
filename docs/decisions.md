# Decisions

This file records each choice of the owner and each technical decision.
Each entry gives the reason. The owner made these choices on 2026-10-16.

## What the app is

- **ZettaLite is ZettaStream for the iPhone 4S on iOS 6.1.3.**
  It reads Stremio addons, IPTV playlists, and single media links, and it
  plays HTTP streams. It is a native Objective-C app with ARC, installed as a
  .deb package on a jailbroken phone.
- **The app has no torrents.**
  A torrent engine on armv7 with 512 MB of RAM is a separate large project.
  The app hides each `infoHash` stream. When a title has no HTTP stream, the
  app shows "This addon gave only torrent streams. Add a debrid key in its
  settings."
- **The app comes with no sources.**
  It is the same as ZettaStream, for the same legal reason. Home shows "Add a
  source in Settings" until you add one.
- **The repository is public.** The licence is MIT.

## Identity

- Bundle ID `io.github.stivengjekaj.zettalite`, display name `ZettaLite`.
- iPhone only. iOS 6.0 or later. Portrait and landscape.
- URL scheme `zettalite://play?url=...`, so that other apps and Safari
  bookmarklets can open a link.

## Sources and input

- **A Sources screen, as in ZettaStream.**
  You paste a list with one URL on each line. The new list replaces the old
  list. A line can be a Stremio addon (`manifest.json`), an M3U playlist, or
  a media link.
- **A box for one link** plays that link at once.
- **Request headers.** The local server fetches each stream itself, so it
  sends the headers of an addon's `behaviorHints.proxyHeaders` and of M3U
  `#EXTVLCOPT` lines.
- **The app speaks TLS with mbedTLS, not with iOS 6** (decided during 0.1,
  2026-10-17). A test on the iPhone 4S showed two faults of the TLS of
  iOS 6:
  - It has no AES-GCM and no ChaCha20. A server that accepts only these
    ciphers fails the handshake. `download.samplelib.com` is one example.
  - It does not know newer root certificates, for example ISRG Root X1 of
    Let's Encrypt.

  mbedTLS 3.6 speaks TLS 1.2 with AES-GCM and ChaCha20. It checks each
  certificate against the Mozilla root list in `resources/cacert.pem`. So a
  Let's Encrypt certificate passes with no question.
- **A certificate that fails the check needs the consent of the user.** The
  app asks one time for each host before it trusts that host. The app never
  trusts all hosts silently.
- **A server that ignores Range still seeks.** The stream starts again from
  the start of the file and drops the bytes before the position. It is slow
  on a large file, but it works.

## The interface

- **The bars are the stock iOS 6 bars, tinted black.**
  The content has a black background, poster rows and grids with
  `UICollectionView`, and the Karla font of ZettaStream, bundled with
  `UIAppFonts`.
- **Five tabs:** Home (catalog rows), Search (in all addons), Library
  (continue watching, watchlist), Live TV (M3U channels), and Settings
  (Sources, playback, subtitles). The title page and the stream picker open
  from Home, Search, and Library.
- **Features from ZettaStream that the app keeps:**
  - continue watching, a watchlist, and watched marks, on the phone only
  - the next episode, with a countdown
  - when a stream fails, the next stream starts
  - stream badges for quality, HDR, codec, and "software decode"
  - a "New episodes" row
  - the cast and "More like this" on a title page
  - subtitle and language settings
  - backup and restore of the library
- **Features from ZettaStream that the app does not have:** profiles (a
  phone has one user), AniSkip, trailers, video filters, and the XMLTV guide.
- **Subtitles** come from subtitle addons (SRT, VTT) and from the text
  subtitles in an MKV file. The app shows them over the video. ASS styles
  become plain text. A picker selects the track, and a setting sets the size.
- **AirPlay and background audio** are on. An audio link continues to play
  when the screen locks.

## Media

### What iOS 6 plays

The system player of iOS 6 plays these formats:

- progressive MP4 and MOV with H.264 and AAC
- MP3 and M4A
- MPEG-TS HLS from an `http://` URL

It does not play HLS from a `file://` URL, AC3 or E-AC3 in TS, MKV, WebM,
HEVC, VP9, or AV1. RetroTube tested this on the same phone.

### FFmpeg

- **FFmpeg does all demuxing, decoding, and TS muxing.**
  It reads MKV, WebM, MP4, fragmented MP4, MPEG-TS, and DASH (`.mpd`).
  Writing new decoders for HEVC, VP9, AC3, and DTS would take years.
- **FFmpeg is LGPL only.** The build has no `--enable-gpl`. It ships as a
  dylib inside the app, so that the MIT licence of the app stays clean. All
  native decoders and demuxers of FFmpeg are LGPL.
- **The version is 7.1.** If the armv7 build blocks, use 6.0. ffmpeg-kit 6.0
  shows that 6.0 builds for armv7 iOS. `config.h` must not use symbols that
  iOS 6 does not have, for example `clock_gettime` (iOS 10).
- **From RetroTube, the app copies only `RTHLSServer`** and the logic of the
  session and its segment cache, with the prefix `ZL`. It does not port
  `RTMP4`, `RTTS`, or `RTRemux`, because FFmpeg does that work.

### Two players

- **H.264 video goes to the system player.**
  FFmpeg remuxes the stream into MPEG-TS segments. The local HLS server on
  `127.0.0.1` serves them. The system player decodes H.264 in hardware up to
  1080p, with AirPlay and low battery use.
- **Audio that the system player refuses is converted.**
  For AC3, E-AC3, DTS, TrueHD, Opus, Vorbis, and FLAC, FFmpeg decodes the
  audio and mixes it down to stereo. Then the AudioConverter of iOS encodes
  it to AAC. The surround channels are lost. Most addon files are H.264 with
  AC3, so most streams stay on this fast path.
- **The software AAC encoder of Apple, not the hardware one** (measured
  during 0.2, 2026-10-17). The research said that iOS 6 has only a hardware
  AAC encoder. The iPhone 4S has two: `aphw` (hardware) and `appl`
  (software). The software one encodes at 19.6 times real time. The hardware
  one failed in a test tool with no audio session. The AAC encoder of FFmpeg
  encodes real sound at about 1 time real time on the A5 chip, so it cannot
  keep up, and it is only the last fallback. With the Apple encoder, a 6
  second segment with 5.1 AC3 takes 1.0 second.
- **Other video codecs go to the own player.**
  For HEVC, VP9, AV1, MPEG-2, and MPEG-4 ASP:
  - FFmpeg decodes the video on 2 threads.
  - OpenGL ES 2 shows the frames with a YUV shader.
  - AudioQueue plays the sound.
  - The controls look like the controls of the system player: seek, pause,
    and pickers for subtitles and audio tracks.
  - The own player has no AirPlay video.
  The other choice was to decode in software and encode again to H.264 with
  the hardware encoder. That adds latency and complexity, and the decode
  stays the bottleneck.

### H.264 that the hardware refuses

The hardware decoder of the A5 chip refuses an H.264 stream that needs more
reference frames than level 4.1 permits: 32768 macroblocks in the decoded
picture buffer. That is 9 frames at 720p and 4 frames at 1080p. A test on
the iPhone 4S (2026-10-17) showed a black picture for a 720p file with 16
reference frames. The same file with 9 reference frames played. A level 5.0
in the header alone did not stop the decoder.

**Decision: the app reads the SPS of each H.264 stream.** A stream with too
many reference frames, or with 10-bit samples, goes to the own player.

### Limits of the A5 chip

`probe/bench.m` measured the decoders on the iPhone 4S (2026-10-17). Each
file is 10 seconds of Big Buck Bunny at 30 frames per second. The value is
the decode speed on 2 threads as a multiple of real time.

| Codec | 360p | 480p | 576p | 720p |
| --- | --- | --- | --- | --- |
| H.264 8-bit (16 reference frames) | | | | 1.32 |
| H.264 10-bit | | 1.44 | | 0.65 |
| HEVC 8-bit | | 1.24 | | 0.57 |
| HEVC 10-bit | | 0.86 (1.03 with no loop filter) | | |
| VP9 | | 2.20 | | 1.13 |
| AV1 (dav1d) | 3.40 | 2.06 | | |
| MPEG-2 | | | 6.06 | |
| MPEG-4 ASP (Xvid) | | 9.42 | | |

The skip of the loop filter helps H.264 and HEVC by 10 to 30%. It does not
help VP9 or AV1.

Audio decode is cheap: AC3 5.1 decodes at 11.6 times real time, DTS 5.1 at
9.1 times, and Opus at 29.6 times.

`src/core/ZLDecodeLimits.m` turns each value into pixels per second. A
stream fits when its pixel rate times 1.2 is below that value. The margin is
for the display and the sound. In the app, VP9 720p at 30 frames per second
dropped 89 of 300 frames, and it is "too heavy" in the table. HEVC 480p
dropped 8 frames, and AV1 480p dropped 2.

### AV1

The AV1 decoder of FFmpeg needs a hardware decoder. The app builds dav1d
1.5.1 (BSD) with its ARM assembly, and FFmpeg uses it.

### Faults in FFmpeg on iOS

`scripts/ffmpeg.sh` changes the source of FFmpeg in four places. The fourth
is a fault that only iOS shows: the NEON synthesis filter of DTS keeps a
pointer in r9 across a call to a C function. iOS lets a function change r9,
so the DTS decoder crashed. The script saves r9 around the call.

**Decision: heavy streams are marked and hidden.**

- Release 0.2 measures the real limit of each codec on the phone. The
  limits stay in a table in the code.
- Autoplay prefers H.264 streams.
- A stream above its limit gets a "Too heavy" badge, and the stream picker
  hides it. The setting "Show heavy streams" shows it.
- When the own player falls behind, it skips the loop filter of the decoder
  before it drops frames.

## Toolchain

- The app builds with the iOS 9.3 SDK of Theos and the clang of the current
  Xcode, as RetroTube does.
- `build.sh` and `fix-sdk.sh` come from RetroTube in their newer form:
  - `-I` and `-D` options
  - objects in `build/obj`
  - `-Werror=unguarded-availability`
  - the C string functions in the libsystem_c stub
- All code is ARM mode (`-marm`). The new Apple linker makes Thumb code that
  crashes on iOS 6 before `main` starts.
- The scripts, the packaging, and the RTTest runner come from RetroTube with
  the prefix `ZL`. Each app stays self-contained.

## Process

- Commit subjects start with `feat:`, `fix:`, `docs:`, `chore:`, `build:`,
  `refactor:`, or `test:`. The first 4 commits have no prefix. They stay as
  they are, because the history is public.
- Releases are 0.x versions up to 1.0.0. Each release gets a tag `vX.Y.Z`,
  notes in `CHANGELOG.md`, and the .deb as an asset on GitHub. Then the
  package goes into the Cydia repository `Stiven-Gjekaj/cydia`.
- On iOS 6, a person installs the .deb with `dpkg -i`. The APT of Cydia on
  iOS 6 supports TLS 1.0 only, and GitHub Pages accepts only TLS 1.2.
