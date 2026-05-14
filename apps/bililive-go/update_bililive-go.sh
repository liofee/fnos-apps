#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PKG_DIR="$SCRIPT_DIR/fnos"

APP_NAME="bililive-go"
APP_DISPLAY_NAME="Bililive-go"
APP_VERSION_VAR="BILILIVE_GO_VERSION"
APP_VERSION="${BILILIVE_GO_VERSION:-latest}"
APP_DEPS=(curl tar)
APP_FPK_PREFIX="bililive-go"
APP_HELP_VERSION_EXAMPLE="0.8.0"

app_set_arch_vars() {
    case "$ARCH" in
        x86) TARBALL_ARCH="amd64" ;;
        arm) TARBALL_ARCH="arm64" ;;
    esac
    info "Tarball arch: $TARBALL_ARCH"
}

app_show_help_examples() {
    cat << EOF
  $0 --arch x86 0.8.0       # Specific version, x86
  $0 0.8.0                  # Specific version, auto-detect arch
EOF
}

app_get_latest_version() {
    info "Getting latest version..."
    local tag
    tag=$(curl -sL "https://api.github.com/repos/bililive-go/bililive-go/releases/latest" 2>/dev/null | \
        grep '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\1/')
    if [ "$APP_VERSION" = "latest" ]; then
        APP_VERSION="$tag"
    fi
    [ -z "$APP_VERSION" ] && error "Unable to get version, specify manually: $0 0.8.0"
    info "Target version: $APP_VERSION"
}

app_download() {
    local download_url="https://github.com/bililive-go/bililive-go/releases/download/v${APP_VERSION}/bililive-linux-${TARBALL_ARCH}.tar.gz"
    info "Downloading ($ARCH): $download_url"
    mkdir -p "$WORK_DIR"
    curl -L -f -o "$WORK_DIR/bililive.tar.gz" "$download_url" || error "Download failed"
    info "Downloaded: $(du -h "$WORK_DIR/bililive.tar.gz" | cut -f1)"
}

app_build_app_tgz() {
    info "Extracting..."
    cd "$WORK_DIR"
    mkdir -p extracted
    tar -xzf bililive.tar.gz -C extracted

    info "Building app.tgz..."
    local dst="$WORK_DIR/app_root"
    mkdir -p "$dst/bin" "$dst/ui"

    local bin
    bin=$(find extracted -name 'bililive*' -type f | head -1)
    [ -z "$bin" ] && { error "bililive binary not found in tar"; exit 1; }
    cp "$bin" "$dst/bililive"
    chmod +x "$dst/bililive"

    cp "$PKG_DIR/bin/bililive-go-server" "$dst/bin/bililive-go-server"
    chmod +x "$dst/bin/bililive-go-server"
    cp -a "$PKG_DIR/ui"/* "$dst/ui/" 2>/dev/null || true

    cd "$dst"
    tar -czf "$WORK_DIR/app.tgz" .
    info "app.tgz: $(du -h "$WORK_DIR/app.tgz" | cut -f1)"
}

source "$REPO_ROOT/scripts/lib/update-common.sh"
main_flow "$@"
