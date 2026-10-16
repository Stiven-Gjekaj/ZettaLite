#!/bin/sh
# Render the icon and the launch images from the SVG files in assets/.
# The PNG files are in git, so that a build does not need rsvg-convert.
# Usage: scripts/icons.sh
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
rsvg-convert -w 57 -h 57 "$ROOT/assets/brand/icon-ios6.svg" -o "$ROOT/resources/Icon.png"
rsvg-convert -w 114 -h 114 "$ROOT/assets/brand/icon-ios6.svg" -o "$ROOT/resources/Icon@2x.png"
rsvg-convert -w 320 -h 480 "$ROOT/assets/launch.svg" -o "$ROOT/resources/Default.png"
rsvg-convert -w 640 -h 960 "$ROOT/assets/launch.svg" -o "$ROOT/resources/Default@2x.png"

# The tab bar icons. iOS 6 uses only their alpha channel.
for name in home search library live settings; do
    rsvg-convert -w 30 -h 30 "$ROOT/assets/tabs/$name.svg" -o "$ROOT/resources/Tab-$name.png"
    rsvg-convert -w 60 -h 60 "$ROOT/assets/tabs/$name.svg" -o "$ROOT/resources/Tab-$name@2x.png"
done
