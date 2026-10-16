#!/bin/sh
# Build FFmpeg for armv7 iOS 6 into build/ffmpeg/.
# The result is one dylib, libzlffmpeg.dylib, and the headers.
# FFmpeg is LGPL. The build has no --enable-gpl and no --enable-nonfree.
# Usage: scripts/ffmpeg.sh
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SDK="$ROOT/sdks/iPhoneOS9.3.sdk"
VERSION=7.1.1
SHA256=733984395e0dbbe5c046abda2dc49a5544e7e0e1e2366bba849222ae9e3a03b1
DL="$ROOT/build/dl"
SRC="$ROOT/build/ffmpeg-src/ffmpeg-$VERSION"
OUT="$ROOT/build/ffmpeg"

mkdir -p "$DL"
TARBALL="$DL/ffmpeg-$VERSION.tar.xz"
if [ ! -f "$TARBALL" ]; then
    curl -sSfL "https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz" -o "$TARBALL"
fi
echo "$SHA256  $TARBALL" | shasum -a 256 -c - >/dev/null

if [ ! -d "$SRC" ]; then
    mkdir -p "$ROOT/build/ffmpeg-src"
    tar -C "$ROOT/build/ffmpeg-src" -xf "$TARBALL"
fi

# The movrelx macro puts a pointer in the non-lazy pointer section with the
# label ".Lpic". On Darwin, only an "L" label is local. The new Apple linker
# stops with an assertion when a pointer in that section has a name.
sed -i '' 's/ldpic           \\rd, \.Lpic\\@, indir=1/ldpic           \\rd, Lnlp\\@, indir=1/;' \
    "$SRC/libavutil/arm/asm.S"
perl -0pi -e 's/(\.non_lazy_symbol_pointer\n)\.Lpic\\@:/$1Lnlp\\@:/' "$SRC/libavutil/arm/asm.S"

TARGET="-target armv7-apple-ios6.0 -isysroot $SDK -Wno-incompatible-sysroot"
STAGE="$ROOT/build/ffmpeg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cd "$STAGE"

# configure asks pkg-config for libxml2. The SDK has libxml2 but no .pc
# file, so a small script gives the answers.
cat >"$STAGE/pkg-config" <<PC
#!/bin/sh
case "\$*" in
    *--cflags*) echo "-I$SDK/usr/include/libxml2" ;;
    *--libs*) echo "-lxml2" ;;
    *--modversion*) echo "2.9.0" ;;
esac
exit 0
PC
chmod +x "$STAGE/pkg-config"

# The decoders, demuxers, and parsers are all the LGPL ones of FFmpeg.
# The app fetches each URL itself, so FFmpeg has no network and no TLS.
"$SRC/configure" \
    --prefix="$STAGE/install" \
    --enable-cross-compile --target-os=darwin --arch=arm --cpu=cortex-a9 \
    --cc="clang" --as="clang" --pkg-config="$STAGE/pkg-config" \
    --extra-cflags="$TARGET -marm -mfpu=neon -I$SDK/usr/include/libxml2" \
    --extra-ldflags="$TARGET" \
    --enable-static --disable-shared --enable-pic \
    --disable-programs --disable-doc --disable-debug \
    --disable-avdevice --disable-avfilter --disable-postproc \
    --disable-network --disable-protocols --enable-protocol=file \
    --disable-encoders --enable-encoder=aac \
    --disable-muxers --enable-muxer=mpegts \
    --disable-videotoolbox --disable-audiotoolbox --disable-securetransport \
    --disable-sdl2 --disable-xlib --disable-bzlib --disable-lzma \
    --disable-iconv --disable-hwaccels --disable-devices --disable-filters \
    --enable-libxml2 --enable-zlib \
    --disable-indevs --disable-outdevs >"$STAGE/configure.log" 2>&1 ||
    { tail -30 "$STAGE/configure.log"; exit 1; }

# The 9.3 SDK has functions that iOS 6 does not have. configure finds them
# and FFmpeg then calls them. Turn them off.
for name in CLOCK_GETTIME; do
    sed -i '' "s/^#define HAVE_$name 1/#define HAVE_$name 0/" config.h
done

make -j"$(sysctl -n hw.ncpu)" >"$STAGE/make.log" 2>&1 || { grep -m 20 -B2 -A5 'error' "$STAGE/make.log"; exit 1; }
make install >/dev/null

# Join the static libraries into one dylib. The app loads it from its bundle.
rm -rf "$OUT"
mkdir -p "$OUT/lib"
cp -R "$STAGE/install/include" "$OUT/include"
L="$STAGE/install/lib"
# libswscale and libavcodec both have half2float.o. Keep one of them.
cp "$L/libswscale.a" "$STAGE/libswscale-dedup.a"
ar d "$STAGE/libswscale-dedup.a" half2float.o
clang $TARGET -marm -Os -c "$ROOT/src/ffmpeg/builtins.c" -o "$STAGE/builtins.o"
clang $TARGET -dynamiclib -marm "$STAGE/builtins.o" \
    -install_name @executable_path/libzlffmpeg.dylib \
    -Wl,-all_load "$L/libavformat.a" "$L/libavcodec.a" "$L/libswresample.a" "$STAGE/libswscale-dedup.a" "$L/libavutil.a" \
    -lz -lxml2 -framework CoreFoundation -framework Foundation \
    -o "$OUT/lib/libzlffmpeg.dylib"
echo "$OUT/lib/libzlffmpeg.dylib"
