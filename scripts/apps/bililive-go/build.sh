#!/bin/bash
set -euo pipefail

VERSION="${VERSION:-}"
TARBALL_ARCH="${TARBALL_ARCH:-${DEB_ARCH:-amd64}}"

[ -z "$VERSION" ] && { echo "VERSION is required" >&2; exit 1; }

echo "==> Building Bililive-go ${VERSION} for ${TARBALL_ARCH}"

# Download upstream binary
DOWNLOAD_URL="https://github.com/bililive-go/bililive-go/releases/download/v${VERSION}/bililive-linux-${TARBALL_ARCH}.tar.gz"
curl -fL -o bililive.tar.gz "$DOWNLOAD_URL"

# Extract
mkdir -p extracted
tar -xzf bililive.tar.gz -C extracted

# Build app.tgz
mkdir -p app_root/bin app_root/ui
BIN=$(find extracted -name 'bililive*' -type f | head -1)
[ -z "$BIN" ] && { echo "bililive binary not found in tar" >&2; exit 1; }
cp "$BIN" app_root/bililive
chmod +x app_root/bililive

cp apps/bililive-go/fnos/bin/bililive-go-server app_root/bin/bililive-go-server
chmod +x app_root/bin/bililive-go-server
cp -a apps/bililive-go/fnos/ui/* app_root/ui/ 2>/dev/null || true

cd app_root
tar -czf ../app.tgz .
cd ..
rm -rf extracted app_root bililive.tar.gz
