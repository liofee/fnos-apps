#!/bin/bash
# Drive a full install→start→probe→stop→uninstall→assert-clean cycle on an .fpk
# inside the fpk-runner Docker container.
#
# Usage:
#   scripts/test/run-fpk-tests.sh <fpk-path> [<slug>]
#
# Slug defaults to inferred from filename.
#
# Requires: docker
#
# Exits 0 on all-pass, 1 on any failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

require_cmd docker "install Docker (CI runners have it; local: brew install docker)"

FPK_PATH="${1:-}"
SLUG="${2:-}"

[ -n "$FPK_PATH" ] || error "Usage: $0 <fpk-path> [<slug>]"
[ -f "$FPK_PATH" ] || error "fpk file not found: $FPK_PATH"

FPK_NAME="$(basename "$FPK_PATH")"
if [ -z "$SLUG" ] && [[ "$FPK_NAME" =~ ^(.+)_[^_]+_(x86|arm)\.fpk$ ]]; then
    SLUG="${BASH_REMATCH[1]}"
fi
[ -n "$SLUG" ] || error "cannot infer slug from filename; pass it explicitly"

REPO="$(repo_root)"
HEALTH_FILE="$REPO/apps/$SLUG/fnos/health.json"
HAS_HEALTH=0
if [ -f "$HEALTH_FILE" ]; then
    HAS_HEALTH=1
    info "Using health.json: apps/$SLUG/fnos/health.json"
else
    warn "no apps/$SLUG/fnos/health.json — defaults will apply"
fi

IMAGE_TAG="${FPK_RUNNER_IMAGE:-fnos-fpk-runner:latest}"

# Build the image if it doesn't exist yet.
if ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
    info "Building fpk-runner image '$IMAGE_TAG'"
    docker build -t "$IMAGE_TAG" "$SCRIPT_DIR/fpk-runner" >&2
fi

FPK_ABS="$(cd "$(dirname "$FPK_PATH")" && pwd)/$(basename "$FPK_PATH")"

MOUNT_ARGS=(-v "$FPK_ABS:/fpk/app.fpk:ro")
RUNNER_ENV=()
if [ "$HAS_HEALTH" -eq 1 ]; then
    HEALTH_ABS="$(cd "$(dirname "$HEALTH_FILE")" && pwd)/$(basename "$HEALTH_FILE")"
    MOUNT_ARGS+=(-v "$HEALTH_ABS:/health.json:ro")
    RUNNER_ENV+=(-e "HEALTH_JSON_SOURCE=/health.json")
fi

info "── Running fpk-runner cycle for $SLUG ($FPK_NAME) ──"
set +e
docker run --rm \
    "${MOUNT_ARGS[@]}" \
    "${RUNNER_ENV[@]}" \
    --entrypoint bash \
    "$IMAGE_TAG" \
    -c '
        set -e
        rc_install=0; rc_start=0; rc_probe=0; rc_stop=0; rc_uninstall=0; rc_clean=0
        /usr/local/bin/fpk-runner install /fpk/app.fpk || rc_install=$?
        if [ "$rc_install" -eq 0 ]; then
            /usr/local/bin/fpk-runner start    || rc_start=$?
            /usr/local/bin/fpk-runner probe    || rc_probe=$?
            /usr/local/bin/fpk-runner logs     || true
            /usr/local/bin/fpk-runner stop     || rc_stop=$?
            /usr/local/bin/fpk-runner uninstall || rc_uninstall=$?
            /usr/local/bin/fpk-runner assert-clean || rc_clean=$?
        fi
        echo ""
        echo "FPK_RUNNER_RESULT install=$rc_install start=$rc_start probe=$rc_probe stop=$rc_stop uninstall=$rc_uninstall clean=$rc_clean"
        exit_code=$(( rc_install + rc_start + rc_probe + rc_stop + rc_uninstall + rc_clean ))
        exit $(( exit_code > 0 ? 1 : 0 ))
    '
RC=$?
set -e

if [ "$RC" -eq 0 ]; then
    pass "fpk-runner cycle PASS for $SLUG"
else
    fail "fpk-runner cycle FAIL for $SLUG (exit $RC)"
fi

report_summary "run-fpk-tests:$SLUG"
