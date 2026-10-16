# ZettaLite

ZettaLite is a small streaming app for an iPhone 4S on iOS 6.1.3
(jailbroken). You install it as a .deb package through Cydia.

You give the app an HTTP link to a media file or stream. The app plays the
link with the iOS 6 media player.

## How ZettaLite differs from ZettaStream

ZettaStream is a stream aggregator for Android TV and Android phones. It
shows the catalogs of Stremio addons, finds streams in all addons, and plays
IPTV playlists as live TV with a guide. It uses Kotlin and Jetpack Compose.

ZettaLite does much less:

- It runs on iOS 6 on an iPhone 4S, not on Android.
- It takes only HTTP links. It has no addons, no catalogs, and no IPTV
  playlists.
- It uses the iOS 6 player. It does not have its own player.
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
