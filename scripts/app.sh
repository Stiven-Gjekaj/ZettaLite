#!/bin/sh
# Build ZettaLite.app into build/.
# Usage: scripts/app.sh
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$ROOT/build/ZettaLite.app"
FFMPEG="$ROOT/build/ffmpeg"
TLS="$ROOT/build/mbedtls"
if [ ! -f "$FFMPEG/lib/libzlffmpeg.dylib" ]; then
    "$ROOT/scripts/ffmpeg.sh" >/dev/null
fi
if [ ! -f "$TLS/ios/libmbedtls.a" ]; then
    "$ROOT/scripts/mbedtls.sh" >/dev/null
fi
rm -rf "$APP"
mkdir -p "$APP"

# shellcheck disable=SC2046
"$ROOT/build.sh" "$APP/ZettaLite" -I"$ROOT/src/core" -I"$ROOT/src/media" -I"$ROOT/src/ui" -I"$FFMPEG/include" -I"$TLS/include" -I"$ROOT/src/tls" \
    $(ls "$ROOT"/src/core/*.m "$ROOT"/src/media/*.m "$ROOT"/src/ui/*.m) \
    "$FFMPEG/lib/libzlffmpeg.dylib" "$TLS/ios/libmbedtls.a" -lz \
    -framework Foundation -framework UIKit -framework CoreGraphics -framework QuartzCore \
    -framework MediaPlayer -framework AVFoundation -framework CoreMedia -framework Security \
    -framework AudioToolbox -framework OpenGLES 2>&1 | grep -v 'liblaunch.dylib' >&2 || true
[ -f "$APP/ZettaLite" ]

cp "$FFMPEG/lib/libzlffmpeg.dylib" "$APP/"
cp "$ROOT/resources/Info.plist" "$APP/Info.plist"
cp "$ROOT"/resources/*.png "$APP/" 2>/dev/null || true
cp "$ROOT"/resources/*.ttf "$APP/" 2>/dev/null || true
cp "$ROOT/resources/cacert.pem" "$APP/"
printf 'APPL????' > "$APP/PkgInfo"
echo "$APP"
