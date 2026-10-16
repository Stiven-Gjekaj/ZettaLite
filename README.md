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

## Get the SDK

1. Download `iPhoneOS9.3.sdk.tar.xz` from the releases of
   <https://github.com/theos/sdks>.
2. Unpack it into `sdks/`, so that `sdks/iPhoneOS9.3.sdk` exists.

The SDK is third-party code. Git ignores `sdks/`.

## Build

Run the SDK fix one time after you unpack the SDK:

    ./fix-sdk.sh

Then build a program:

    ./build.sh OUT SRC.m -framework Foundation

`build.sh` makes armv7 code in ARM mode (`-marm`). It compiles each source
with ARC and links without ARC.

## Run on the phone

The phone is at `iphone4s` over SSH (a USB iproxy tunnel on port 2222).

    scp OUT iphone4s:/tmp/
    ssh iphone4s 'ldid -S /tmp/OUT && /tmp/OUT'
