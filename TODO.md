# Roadmap

Each release adds one big part. The risky media work comes first. The reason
for each choice is in [docs/decisions.md](docs/decisions.md).

## 0.1: the link player (done, 2026-10-17)

- Copy the newer `build.sh` and `fix-sdk.sh` from RetroTube.
- Copy the scripts, the packaging, and the RTTest runner, with the prefix `ZL`.
- Build FFmpeg 7.1 LGPL for armv7 iOS 6 as a dylib. Use 6.0 if 7.1 blocks.
- Copy `RTHLSServer` and the segment cache as `ZLHLSServer`.
- Speak TLS with mbedTLS and the Mozilla root list, because the TLS of iOS 6
  fails with many servers.
- Remux MKV, WebM, MP4, fragmented MP4, MPEG-TS, and DASH with H.264 into
  TS segments for the system player.
- Add the box for one link and the `zettalite://play?url=` scheme.
- Ask one time for each host that fails the trust check.

## 0.2: software decode (done, 2026-10-17)

- Build dav1d for armv7, because the AV1 decoder of FFmpeg needs a hardware
  decoder.
- Convert AC3, E-AC3, DTS, TrueHD, Opus, Vorbis, and FLAC to stereo AAC.
  Use the software AudioConverter of Apple, with the FFmpeg AAC encoder as
  the fallback.
- Add the own player for HEVC, VP9, AV1, MPEG-2, and MPEG-4 ASP: FFmpeg on
  2 threads, OpenGL ES 2, and AudioQueue.
- Measure the real limit of each codec on the phone, and put it in the table.
- Skip the loop filter when the own player falls behind.

## 0.3: addons (done, 2026-10-17)

- Add the Sources screen: one URL on each line.
- Read Stremio manifests, catalogs, and meta.
- Add the five tabs, the black theme, and the Karla font.
- Add Home with poster rows, Search in all addons, and the title page with
  seasons, episodes, cast, and "More like this".
- Show "Add a source in Settings" when there are no sources.

## 0.4: streams (done, 2026-10-17)

- Ask all addons for streams at the same time.
- Hide torrent streams. Show the message about a debrid key.
- Add the stream picker with badges for quality, HDR, codec, "software
  decode", and "Too heavy".
- Prefer H.264 for autoplay. Start the next stream when one fails.
- Send the headers of `behaviorHints.proxyHeaders`.

## 0.5: the library (done, 2026-10-17)

- Add continue watching, the watchlist, and watched marks.
- Add the next episode with a countdown, and the "New episodes" row.
- Add backup and restore of the library.

## 0.6: IPTV (done, 2026-10-17)

- Read M3U playlists, with the headers of `#EXTVLCOPT` lines.
- Add the Live TV tab with the channels in a table.
- Play HLS channels in the system player. Play raw MPEG-TS channels through
  the local server.

## 0.7: subtitles (done, 2026-10-17)

- Read SRT and VTT from subtitle addons and the text subtitles of MKV files.
- Show them over both players, with a picker and a size setting.
- Add the language settings.

## 1.0.0 (done, 2026-10-17)

- Check each feature on the iPhone 4S with iOS 6.1.3.
- Release the .deb, and add it to the Cydia repository.
