# Changelog

Every release is written here, newest first. A version is
`MAJOR.MINOR.PATCH`. Before 1.0.0, each big addition raises the minor number.
Each release on GitHub has the `.deb` package as an asset.

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
