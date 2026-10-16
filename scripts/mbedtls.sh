#!/bin/sh
# Build mbedTLS for armv7 iOS 6 and for this Mac, into build/mbedtls/.
# The TLS of iOS 6 has no AES-GCM and no ChaCha20, and many servers accept
# only these ciphers now. The app speaks TLS with mbedTLS instead.
# mbedTLS is Apache-2.0.
# Usage: scripts/mbedtls.sh
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SDK="$ROOT/sdks/iPhoneOS9.3.sdk"
VERSION=3.6.2
SHA256=8b54fb9bcf4d5a7078028e0520acddefb7900b3e66fec7f7175bb5b7d85ccdca
DL="$ROOT/build/dl"
SRC="$ROOT/build/mbedtls-src/mbedtls-$VERSION"
OUT="$ROOT/build/mbedtls"

mkdir -p "$DL"
TARBALL="$DL/mbedtls-$VERSION.tar.bz2"
if [ ! -f "$TARBALL" ]; then
    curl -sSfL "https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-$VERSION/mbedtls-$VERSION.tar.bz2" -o "$TARBALL"
fi
echo "$SHA256  $TARBALL" | shasum -a 256 -c - >/dev/null
if [ ! -d "$SRC" ]; then
    mkdir -p "$ROOT/build/mbedtls-src"
    tar -C "$ROOT/build/mbedtls-src" -xf "$TARBALL"
fi

rm -rf "$OUT"
mkdir -p "$OUT/include"
cp -R "$SRC/include/mbedtls" "$SRC/include/psa" "$OUT/include/"

CONFIG="-DMBEDTLS_USER_CONFIG_FILE=\"zl_mbedtls_config.h\" -I$ROOT/src/tls"

build() {
    name=$1
    shift
    mkdir -p "$OUT/$name/obj"
    for file in "$SRC"/library/*.c "$ROOT/src/tls/ms_time.c"; do
        obj="$OUT/$name/obj/$(basename "$file" .c).o"
        # shellcheck disable=SC2086
        clang "$@" -Os $CONFIG -I"$SRC/include" -I"$SRC/library" -c "$file" -o "$obj" &
        # Run as many compilers as the Mac has cores.
        while [ "$(jobs -r | wc -l)" -ge "$(sysctl -n hw.ncpu)" ]; do sleep 0.05; done
    done
    wait
    count=$(ls "$SRC"/library/*.c | wc -l)
    built=$(ls "$OUT/$name"/obj/*.o | wc -l)
    if [ "$built" -ne "$((count + 1))" ]; then
        echo "mbedtls: $built of $((count + 1)) files compiled" >&2
        exit 1
    fi
    ar rcs "$OUT/$name/libmbedtls.a" "$OUT/$name"/obj/*.o
}

build ios -target armv7-apple-ios6.0 -isysroot "$SDK" -Wno-incompatible-sysroot -marm
build mac -mmacosx-version-min=10.9
echo "$OUT"
