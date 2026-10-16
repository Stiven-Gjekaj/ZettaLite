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

# The DASH demuxer opens each URL with its own HTTP code, not with the io_open
# hook of the app. Make it use the hook, as the HLS demuxer does, so that the
# app fetches each segment with its headers and its trust.
perl -pi -e 's/ret = ffio_open_whitelist\(pb, url, AVIO_FLAG_READ, c->interrupt_callback, &tmp, s->protocol_whitelist, s->protocol_blacklist\);/ret = s->io_open(s, pb, url, AVIO_FLAG_READ, &tmp);/;
    s/ret = ffio_open_whitelist\(&in, url, AVIO_FLAG_READ, c->interrupt_callback, &opts, s->protocol_whitelist, s->protocol_blacklist\);/ret = s->io_open(s, &in, url, AVIO_FLAG_READ, &opts);/;
    s/^        avio_close\(in\);/        ff_format_io_close(s, &in);/' "$SRC/libavformat/dashdec.c"

# The NEON synthesis filter of DTS keeps a pointer in r9 across a call to a
# C function. On iOS, r9 is a scratch register, so the C function can change
# it, and the decoder then crashes. Save r9 around the call.
perl -0pi -e 's/(VFP     vpush           \{d0\}\n)(        blx             r12\n)(VFP     vpop            \{d0\}\n)/        push            {r9}\n$1$2$3        pop             {r9}\n/ unless /push            \{r9\}/' \
    "$SRC/libavcodec/arm/synth_filter_neon.S"

TARGET="-target armv7-apple-ios6.0 -isysroot $SDK -Wno-incompatible-sysroot"
STAGE="$ROOT/build/ffmpeg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cd "$STAGE"

# FFmpeg decodes AV1 with dav1d.
DAV1D="$ROOT/build/dav1d"
if [ ! -f "$DAV1D/lib/libdav1d.a" ]; then
    "$ROOT/scripts/dav1d.sh" >/dev/null
fi

# configure asks pkg-config for libxml2 and dav1d. The SDK has libxml2 but
# no .pc file, so a small script gives the answers.
cat >"$STAGE/pkg-config" <<PC
#!/bin/sh
case "\$*" in
    *dav1d*--cflags* | *--cflags*dav1d*) echo "-I$DAV1D/include" ;;
    *dav1d*--libs* | *--libs*dav1d*) echo "-L$DAV1D/lib -ldav1d" ;;
    *dav1d*--modversion* | *--modversion*dav1d*) echo "1.5.1" ;;
    *--cflags*) echo "-I$SDK/usr/include/libxml2" ;;
    *--libs*) echo "-lxml2" ;;
    *--modversion*) echo "2.9.0" ;;
esac
exit 0
PC
chmod +x "$STAGE/pkg-config"

# The decoders, demuxers, and parsers are all the LGPL ones of FFmpeg.
# The app fetches each URL itself through its io_open hook, so FFmpeg has
# no TLS. The HLS and DASH demuxers still check that an http protocol exists
# before they call the hook, so the http protocol stays in the build.
"$SRC/configure" \
    --prefix="$STAGE/install" \
    --enable-cross-compile --target-os=darwin --arch=arm --cpu=cortex-a9 \
    --cc="clang" --as="clang" --pkg-config="$STAGE/pkg-config" \
    --extra-cflags="$TARGET -marm -mfpu=neon -I$SDK/usr/include/libxml2" \
    --extra-ldflags="$TARGET" \
    --enable-static --disable-shared --enable-pic \
    --disable-programs --disable-doc --disable-debug \
    --disable-avdevice --disable-avfilter --disable-postproc \
    --disable-protocols --enable-protocol=file,http,tcp \
    --disable-encoders --enable-encoder=aac \
    --disable-muxers --enable-muxer=mpegts \
    --disable-videotoolbox --disable-audiotoolbox --disable-securetransport \
    --disable-sdl2 --disable-xlib --disable-bzlib --disable-lzma \
    --disable-iconv --disable-hwaccels --disable-devices --disable-filters \
    --enable-libxml2 --enable-zlib --enable-libdav1d \
    --disable-indevs --disable-outdevs >"$STAGE/configure.log" 2>&1 ||
    { tail -30 "$STAGE/configure.log"; exit 1; }

# The 9.3 SDK has functions that iOS 6 does not have. configure finds them
# and FFmpeg then calls them. Turn them off.
for name in CLOCK_GETTIME; do
    sed -i '' "s/^#define HAVE_$name 1/#define HAVE_$name 0/" config.h
done

# The https protocol needs a TLS library. The app never lets FFmpeg open a
# URL, so the https protocol only has to exist for the check of the
# demuxers. Turn it on without TLS.
sed -i '' 's/^#define CONFIG_HTTPS_PROTOCOL 0/#define CONFIG_HTTPS_PROTOCOL 1/' config_components.h
sed -i '' 's/^    &ff_http_protocol,/&\
    \&ff_https_protocol,/' libavformat/protocol_list.c

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
    "$DAV1D/lib/libdav1d.a" \
    -lz -lxml2 -framework CoreFoundation -framework Foundation \
    -o "$OUT/lib/libzlffmpeg.dylib"
echo "$OUT/lib/libzlffmpeg.dylib"
