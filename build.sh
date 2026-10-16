#!/bin/sh
# Build one armv7 command line tool for iOS 6.
# Usage: ./build.sh OUTPUT SOURCE.m [more sources] [-framework X ...]
# The script compiles each source with ARC, then links without ARC.
# The link step has no -fobjc-arc, so clang does not ask for libarclite.
# All code is ARM mode (-marm). The new Apple linker makes Thumb code that
# crashes on iOS 6 before main starts.
set -e

ROOT=$(cd "$(dirname "$0")" && pwd)
SDK="$ROOT/sdks/iPhoneOS9.3.sdk"
OUT=$1
shift

OBJS=""
LINK=""
while [ $# -gt 0 ]; do
    case "$1" in
        -framework|-l*)
            if [ "$1" = "-framework" ]; then LINK="$LINK -framework $2"; shift; else LINK="$LINK $1"; fi
            ;;
        *)
            obj="${1%.*}.o"
            clang -target armv7-apple-ios6.0 -isysroot "$SDK" -Wno-incompatible-sysroot \
                -marm -fobjc-arc -Os -c "$1" -o "$obj"
            OBJS="$OBJS $obj"
            ;;
    esac
    shift
done

# shellcheck disable=SC2086
clang -target armv7-apple-ios6.0 -isysroot "$SDK" -Wno-incompatible-sysroot $OBJS $LINK -o "$OUT"
