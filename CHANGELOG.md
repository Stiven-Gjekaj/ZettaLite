# Changelog

Every release is written here, newest first. A version is
`MAJOR.MINOR.PATCH`. Before 1.0.0, each big addition raises the minor number.
Each release on GitHub has the `.deb` package as an asset.

## 0.7.0 (2026-10-17)

Subtitles.

- Both players show subtitles. Subs in the player gives the choices: Off,
  the text subtitles inside the file, and the subtitles of the addons.
- The app reads SRT and WebVTT files, and SubRip, WebVTT, mov_text, and ASS
  subtitles inside MKV and MP4 files. It removes the styles.
- The app asks the subtitle addons, for example OpenSubtitles v3, for each
  title, and it also reads the subtitles that a stream gives.
- Settings, Playback, has Subtitle language and Subtitle size. The player
  picks the language at the start, from the file first.
- Fix: the tests on the phone link CoreGraphics again, and an addon test
  makes its URL as a pasted source makes it, so that iOS 6 accepts it.

## 0.6.0 (2026-10-17)

Live TV.

- The Live TV tab shows the channels of the M3U playlists and the media
  links in Sources. The first screen shows the favourite channels and the
  groups. The search bar finds a channel by name.
- The app reads the logo, the group, and the headers of each channel, from
  `#EXTINF`, `#EXTGRP`, `#EXTVLCOPT`, `#EXTHTTP`, and links with `|`.
- A `.m3u8` link can be a list of channels or one HLS stream. The app reads
  it and knows which.
- HLS channels play in the system player. MPEG-TS channels play through the
  live remux.
- The star marks a favourite channel. The backup keeps the favourites.
- `zettalite://live?group=NAME` opens a group.
  `zettalite://live?channel=NAME` plays a channel.
- The log shows each link that opens the app.

## 0.5.0 (2026-10-17)

The library.

- The Library tab shows Continue watching, New episodes, and the
  watchlist. A tap on a title in Continue watching or New episodes plays it
  at once.
- Home starts with Continue watching and New episodes.
- A film or an episode starts where it stopped. It counts as watched after
  90%.
- Play on a series plays the next episode to watch, and says which one, for
  example "Play S1 E3". A film with progress says Resume.
- At the end of an episode, a countdown of 10 seconds starts the next
  episode, from the same source and quality when the addon gives a
  bingeGroup. Play now and Cancel are on the countdown. Settings, Playback,
  Play the next episode, turns it off.
- + List adds a title to the watchlist.
- The episodes show a watched mark and a progress bar. A long press on an
  episode gives Play, Sources, Mark as watched, and Mark the episodes before
  as watched.
- New episodes: the app checks the series of the library one time in 6
  hours, and shows the episodes of the last 14 days that are not watched.
- Settings, Backup and restore: a backup of the library, the sources, the
  trusted hosts, and the settings goes to the clipboard and to a file that
  iTunes File Sharing shows.
- A `zettalite://tab` link goes back to the first screen of the tab.

## 0.4.0 (2026-10-17)

Streams.

- Play starts the best stream at once. The app asks all addons at the same
  time, waits at most 8 seconds, and picks the stream that the phone plays
  best: H.264 up to 1080p plays in hardware. The loading box shows which
  source plays.
- When a stream fails, the next best one starts, up to 5 sources.
- Sources shows all streams, best first. Each stream shows badges for the
  quality, HDR or Dolby Vision, the codec, the audio, the size, and
  "Software" or "Too heavy", and all of its text.
- A stream that is too heavy for the A5 chip does not show. Settings,
  Playback, Show heavy streams, shows it.
- Torrent streams do not show. When an addon gives only torrents, the app
  says to add a debrid key in the settings of the addon.
- The app sends the headers of an addon (`behaviorHints.proxyHeaders`) with
  each request of a stream, also for the segments of HLS and DASH.
- A long press on an episode shows its sources.
- Settings, Playback: Autoplay, Show heavy streams, Play the next episode,
  and Audio language.
- `zettalite://watch?type=TYPE&id=ID` plays the best stream of a title or an
  episode.
- A link from another app no longer finds no streams when the addons have
  not loaded yet.

## 0.3.0 (2026-10-17)

Stremio addons.

- Five tabs: Home, Search, Library, Live TV, and Settings. Library and Live
  TV fill in 0.5 and 0.6.
- Settings, Sources: paste a list with one link on each line. A Stremio
  addon (`manifest.json`) gives catalogs, titles, and streams. The list shows
  each addon that loaded and each link that failed.
- Home shows a banner of featured titles and one row of posters for each
  catalog. A filter at the top shows all rows, the films, the series, or the
  other types. A tap on the name of a row shows all of its titles in a grid,
  with more pages and a genre filter.
- Search asks each addon with search at the same time.
- The page of a title shows the picture, the facts, the genres, the
  description, the director, the cast, the seasons and the episodes, and
  "More like this".
- Play shows the HTTP streams of all addons. Torrent streams do not show.
- WebP posters show. iOS 6 cannot decode WebP, so FFmpeg does it.
- New links: `zettalite://title?type=TYPE&id=ID`, `zettalite://search?q=TEXT`,
  and `zettalite://tab?name=NAME`.
- The app uses the Karla font of ZettaStream.

## 0.2.0 (2026-10-17)

The own player.

- HEVC, VP9, AV1, MPEG-2, MPEG-4 ASP (Xvid and DivX), 10-bit H.264, and
  H.264 with more reference frames than the hardware accepts play in the own
  player. It decodes the video on 2 cores and shows it with OpenGL ES 2.
- The own player has Done, play and pause, a seek bar, an audio track
  picker, and Fit or Fill. A tap shows and hides the controls. A double tap
  changes Fit and Fill.
- The sound goes on in the background.
- AV1 decodes with dav1d.
- AC3, DTS, and the other audio that iOS 6 cannot play now change into AAC
  ten times faster, with the AAC encoder of Apple. With 0.1.0, the sound of
  such a file came slower than real time.
- A DTS track does not crash the app any more.
- `zettalite://play?url=URL&t=SECONDS` starts at a second.

## 0.1.0 (2026-10-17)

The link player.

- Paste a link and press Play. MKV, WebM, MP4, MOV, MPEG-TS, HLS, and DASH
  play.
- FFmpeg 7.1 on the phone remuxes H.264 into HLS for the system player, so
  the hardware decoder plays it up to 1080p, with seek and AirPlay.
- Audio that iOS 6 cannot play (AC3, E-AC3, DTS, TrueHD, Opus, Vorbis, FLAC)
  becomes stereo AAC on the phone.
- A stream that cannot seek, for example a live channel, plays as a live
  stream.
- The app speaks TLS 1.2 with AES-GCM and ChaCha20 through mbedTLS, and it
  knows the newer root certificates, for example the root of Let's Encrypt.
  The TLS of iOS 6 cannot connect to many servers now.
- For a certificate that fails the check, the app asks one time before it
  trusts the host.
- Other apps and Safari bookmarklets can open `zettalite://play?url=URL`.
- The app gives an error for HEVC, VP9, AV1, 10-bit H.264, and H.264 with
  more reference frames than the hardware accepts. Release 0.2 plays them in
  software.
