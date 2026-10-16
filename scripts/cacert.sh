#!/bin/sh
# Get the newest Mozilla root certificates from the curl project into
# resources/cacert.pem. The app checks each TLS certificate against them.
# The file is MPL-2.0.
# Usage: scripts/cacert.sh
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
curl -sSfL https://curl.se/ca/cacert.pem -o "$ROOT/resources/cacert.pem.new"
grep -q 'BEGIN CERTIFICATE' "$ROOT/resources/cacert.pem.new"
mv "$ROOT/resources/cacert.pem.new" "$ROOT/resources/cacert.pem"
grep -c 'BEGIN CERTIFICATE' "$ROOT/resources/cacert.pem"
