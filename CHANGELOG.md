# Changelog

Every release is written here, newest first. A version is
`MAJOR.MINOR.PATCH`. Before 1.0.0, each big addition raises the minor number.
Each release on GitHub has the `.deb` package as an asset.

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
