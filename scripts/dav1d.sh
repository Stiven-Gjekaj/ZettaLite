#!/bin/sh
# Build dav1d, the AV1 decoder of VideoLAN, for armv7 iOS 6 into
# build/dav1d/. The AV1 decoder of FFmpeg needs a hardware decoder, and the
# A5 chip has none. dav1d is BSD-2-Clause.
# Meson and Ninja go into a Python environment in build/, so the Mac does
# not change.
# Usage: scripts/dav1d.sh
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SDK="$ROOT/sdks/iPhoneOS9.3.sdk"
VERSION=1.5.1
SHA256=401813f1f89fa8fd4295805aa5284d9aed9bc7fc1fdbe554af4292f64cbabe21
DL="$ROOT/build/dl"
SRC="$ROOT/build/dav1d-src/dav1d-$VERSION"
OUT="$ROOT/build/dav1d"
VENV="$ROOT/build/venv"

mkdir -p "$DL"
TARBALL="$DL/dav1d-$VERSION.tar.xz"
if [ ! -f "$TARBALL" ]; then
    curl -sSfL "https://downloads.videolan.org/pub/videolan/dav1d/$VERSION/dav1d-$VERSION.tar.xz" -o "$TARBALL"
fi
echo "$SHA256  $TARBALL" | shasum -a 256 -c - >/dev/null
if [ ! -d "$SRC" ]; then
    mkdir -p "$ROOT/build/dav1d-src"
    tar -C "$ROOT/build/dav1d-src" -xf "$TARBALL"
fi
if [ ! -x "$VENV/bin/meson" ]; then
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install -q meson ninja
fi

STAGE="$ROOT/build/dav1d-stage"
rm -rf "$STAGE" "$OUT"
mkdir -p "$STAGE"
cat >"$STAGE/cross.txt" <<CROSS
[binaries]
c = 'clang'
ar = 'ar'
strip = 'strip'

[built-in options]
c_args = ['-target', 'armv7-apple-ios6.0', '-isysroot', '$SDK', '-Wno-incompatible-sysroot', '-marm']
c_link_args = ['-target', 'armv7-apple-ios6.0', '-isysroot', '$SDK', '-Wno-incompatible-sysroot']

[host_machine]
system = 'darwin'
cpu_family = 'arm'
cpu = 'armv7'
endian = 'little'
CROSS

PATH="$VENV/bin:$PATH" meson setup "$STAGE/build" "$SRC" --cross-file "$STAGE/cross.txt" \
    --prefix="$OUT" --libdir=lib --buildtype=release --default-library=static \
    -Denable_tools=false -Denable_tests=false -Denable_examples=false -Dbitdepths=8,16 >"$STAGE/setup.log" 2>&1 ||
    { tail -30 "$STAGE/setup.log"; exit 1; }
PATH="$VENV/bin:$PATH" ninja -C "$STAGE/build" install >"$STAGE/build.log" 2>&1 ||
    { grep -m 20 -B2 -A5 'error' "$STAGE/build.log"; exit 1; }
echo "$OUT/lib/libdav1d.a"
