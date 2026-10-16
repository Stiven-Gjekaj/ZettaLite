# ZettaLite

ZettaLite is a streaming app for an iPhone 4S on iOS 6.1.3 (jailbroken).
You install it as a .deb package.

It reads Stremio addons, IPTV playlists, and single media links, and it
plays their HTTP streams. FFmpeg on the phone changes each stream into a
form that the iOS 6 player plays. For a codec that the phone cannot decode
in hardware, the app has its own software player.

The app is in development. [TODO.md](TODO.md) has the plan, and
[docs/decisions.md](docs/decisions.md) has each decision and its reason.

## How ZettaLite differs from ZettaStream

ZettaStream is a stream aggregator for Android TV and Android phones. It
shows the catalogs of Stremio addons, finds streams in all addons, and plays
IPTV playlists as live TV with a guide. It uses Kotlin and Jetpack Compose.

ZettaLite brings the same idea to iOS 6, with these differences:

- It runs on an iPhone 4S, not on Android.
- It plays HTTP streams only. It has no torrents.
- It has no profiles, AniSkip, trailers, video filters, or TV guide.
- It is written in Objective-C and builds with a command line script, not
  with Gradle.

## Install

You need an iPhone, iPod touch, or iPad with iOS 6 and a jailbreak.

1. Download the `.deb` file from the
   [latest release](https://github.com/Stiven-Gjekaj/ZettaLite/releases/latest).
2. Copy it to the phone, for example with `scp` to `/tmp/`.
3. On the phone, as root: `dpkg -i /tmp/io.github.stivengjekaj.zettalite_*.deb`.

To remove the app: `dpkg -r io.github.stivengjekaj.zettalite`.

## Add your sources

ZettaLite comes with no sources. Open Settings, then Sources, paste your
list, and press Save. Put one link on each line:

| Line | Example | Gives |
| ---- | ------- | ----- |
| A Stremio addon | `https://.../manifest.json` | Catalogs, titles, streams, subtitles |
| An IPTV playlist | `https://.../playlist.m3u` | Live channels |
| A media link | `https://.../film.mkv` | One video |

The new list replaces the old list. The order of the lines sets the order of
the rows on Home.

ZettaLite plays HTTP streams only. A torrent addon gives HTTP links when you
add a debrid key in its settings.

## Links from other apps

Other apps and Safari bookmarklets can open these links. Each value is
percent-encoded.

| Link | Does |
| ---- | ---- |
| `zettalite://play?url=URL&t=SECONDS` | Plays URL, from SECONDS |
| `zettalite://title?type=TYPE&id=ID` | Opens the page of a title, for example `type=movie&id=tt0111161` |
| `zettalite://search?q=TEXT` | Searches in all addons |
| `zettalite://tab?name=NAME` | Opens `home`, `search`, `library`, `live`, or `settings` |

Settings, Play a link plays one pasted link.

## Build

You need a Mac with Xcode, the iOS 9.3 SDK of Theos, and `rsvg-convert` and
`dpkg-deb` from Homebrew. The media tests also need `ffmpeg` on the Mac.

1. Download `iPhoneOS9.3.sdk.tar.xz` from the releases of
   [theos/sdks](https://github.com/theos/sdks/releases) and unpack it into
   `sdks/`. The result is `sdks/iPhoneOS9.3.sdk`. Git does not track `sdks/`.
2. Run `./fix-sdk.sh` one time. It changes the SDK stubs for the new Apple
   linker and for iOS 6.
3. Build:

| Command | Result |
| ------- | ------ |
| `scripts/app.sh` | `build/ZettaLite.app`. It builds FFmpeg and mbedTLS the first time. |
| `scripts/deb.sh` | The Cydia package in `build/` |
| `scripts/install.sh` | Builds the app, copies it to the phone, and opens it |
| `scripts/test.sh` | The tests of `src/core`, on the Mac |
| `scripts/test.sh --phone` | All the tests, on the phone |
| `ZL_LIVE=1 scripts/test.sh` | Also the tests that use the internet |
| `scripts/ffmpeg.sh` | FFmpeg as one LGPL dylib in `build/ffmpeg/` |
| `scripts/mbedtls.sh` | mbedTLS in `build/mbedtls/` |

The phone scripts use `ssh iphone4s`. Set up that host in `~/.ssh/config`,
for example with a USB tunnel of `iproxy` on port 2222.

`build.sh` builds one armv7 binary. It compiles with ARC and links without
ARC, and all code is in ARM mode (`-marm`). The new Apple linker makes Thumb
code that crashes on iOS 6 before `main` starts.

To run a tool on the phone:

```
./build.sh build/X probe/X.m -framework Foundation
scp build/X iphone4s:/tmp/
ssh iphone4s 'ldid -S /tmp/X && /tmp/X'
```

[docs/architecture.md](docs/architecture.md) tells how the parts fit
together.

## Licence

MIT. See [LICENSE](LICENSE). The app includes FFmpeg (LGPL 2.1), mbedTLS
(Apache 2.0), and the Mozilla root certificates (MPL 2.0). See
[docs/architecture.md](docs/architecture.md#third-party-code).
