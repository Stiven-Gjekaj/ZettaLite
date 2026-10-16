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
mkdir -p "$OUT"
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
        $CORE $MEDIA $CORE_TESTS $MEDIA_TESTS "$FFMPEG/lib/libzlffmpeg.dylib" \
        -framework Foundation -framework Security -framework AudioToolbox 2>&1 | grep -v 'liblaunch.dylib' >&2 || true
    ssh iphone4s 'mkdir -p /tmp/zltests'
    scp -q "$OUT/zltests-armv7" iphone4s:/tmp/zltests/zltests
    scp -q "$FFMPEG/lib/libzlffmpeg.dylib" iphone4s:/tmp/zltests/
    if [ -d "$ROOT/tests/media/fixtures" ]; then
        scp -q -r "$ROOT/tests/media/fixtures" iphone4s:/tmp/zltests/
    fi
    ssh iphone4s "cd /tmp/zltests && ldid -S libzlffmpeg.dylib && ldid -S zltests &&
        ZL_LIVE=${ZL_LIVE:-} ./zltests $*"
else
    # shellcheck disable=SC2086
    clang -fobjc-arc -Wall -Werror -mmacosx-version-min=10.9 -I"$ROOT/src/core" -I"$ROOT/tests" $CORE $CORE_TESTS \
        -framework Foundation -framework Security -o "$OUT/zltests"
    "$OUT/zltests" "$@"
fi
