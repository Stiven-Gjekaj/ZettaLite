#!/bin/sh
# Build and run the tests.
# Usage: scripts/test.sh [--phone] [NAME]
# With no option, the tests of src/core operate on this Mac.
# With --phone, the tests of src/core and src/media operate on the iPhone at
# "ssh iphone4s".
# NAME runs only the tests with NAME in their name.
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/tests"
FFMPEG="$ROOT/build/ffmpeg"
TLS="$ROOT/build/mbedtls"
mkdir -p "$OUT"
if [ ! -f "$TLS/mac/libmbedtls.a" ]; then
    "$ROOT/scripts/mbedtls.sh" >/dev/null
fi
# The tests find the root certificates next to the test program.
cp "$ROOT/resources/cacert.pem" "$OUT/"
CORE=$(ls "$ROOT"/src/core/*.m 2>/dev/null || true)
CORE_TESTS=$(ls "$ROOT"/tests/*.m "$ROOT"/tests/core/*.m 2>/dev/null || true)

if [ "$1" = "--phone" ]; then
    shift
    if [ ! -f "$FFMPEG/lib/libzlffmpeg.dylib" ]; then
        "$ROOT/scripts/ffmpeg.sh" >/dev/null
    fi
    MEDIA=$(ls "$ROOT"/src/media/*.m 2>/dev/null || true)
    MEDIA_TESTS=$(ls "$ROOT"/tests/media/*.m 2>/dev/null || true)
    # shellcheck disable=SC2086
    "$ROOT/build.sh" "$OUT/zltests-armv7" -I"$ROOT/src/core" -I"$ROOT/src/media" -I"$ROOT/tests" -I"$FFMPEG/include" \
        -I"$TLS/include" -I"$ROOT/src/tls" $CORE $MEDIA $CORE_TESTS $MEDIA_TESTS "$FFMPEG/lib/libzlffmpeg.dylib" \
        "$TLS/ios/libmbedtls.a" -lz \
        -framework Foundation -framework Security -framework AudioToolbox >"$OUT/build.log" 2>&1 ||
        { grep -v 'liblaunch.dylib' "$OUT/build.log" >&2; exit 1; }
    ssh iphone4s 'mkdir -p /tmp/zltests'
    scp -q "$OUT/zltests-armv7" iphone4s:/tmp/zltests/zltests
    scp -q "$FFMPEG/lib/libzlffmpeg.dylib" "$ROOT/resources/cacert.pem" iphone4s:/tmp/zltests/
    if [ ! -d "$ROOT/build/fixtures" ]; then
        "$ROOT/scripts/fixtures.sh" >/dev/null
    fi
    if ! ssh iphone4s 'test -d /tmp/zltests/fixtures/dash'; then
        # The sftp server of the phone cannot make a new directory, so copy with tar.
        COPYFILE_DISABLE=1 tar --no-xattrs -C "$ROOT/build" -cf - fixtures | ssh iphone4s 'tar -C /tmp/zltests -xf -'
    fi
    ssh iphone4s "cd /tmp/zltests && ldid -S libzlffmpeg.dylib && ldid -S zltests &&
        ZL_LIVE=${ZL_LIVE:-} ./zltests $*"
else
    # shellcheck disable=SC2086
    clang -fobjc-arc -Wall -Werror -mmacosx-version-min=10.9 -I"$ROOT/src/core" -I"$ROOT/tests" \
        -I"$TLS/include" -I"$ROOT/src/tls" $CORE $CORE_TESTS "$TLS/mac/libmbedtls.a" -lz \
        -framework Foundation -framework Security -o "$OUT/zltests"
    "$OUT/zltests" "$@"
fi
