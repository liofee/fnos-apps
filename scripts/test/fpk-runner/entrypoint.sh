#!/bin/bash
# fpk-runner — fnOS install-fpk simulator for L3 testing.
#
# Subcommands:
#   install <fpk-path>                Extract + run install_init + install_callback
#   start                             Run cmd/main start
#   probe                             HTTP/TCP probe per health.json
#   stop                              Run cmd/main stop
#   uninstall                         Run uninstall_init + uninstall_callback (with data delete)
#   logs                              Cat LOG_FILE for the installed app
#   assert-clean                      Assert no stale PID, no port listening, no leftover data
#   help                              Show this help
#
# State (per container):
#   /vol1/<appname>                 → TRIM_PKGVAR (app data)
#   /var/apps/<appname>/etc         → TRIM_PKGETC (app etc)
#   /usr/trim/apps/<appname>        → TRIM_APPDEST (app code)
#   /var/run/fpk-runner.env         → exports for subsequent subcommand calls

set -euo pipefail

STATE_DIR=/var/run/fpk-runner
STATE_ENV="$STATE_DIR/env"
EXTRACT_BASE=/var/run/fpk-runner/extracted

mkdir -p "$STATE_DIR"

_C_GREEN=$'\033[0;32m'
_C_RED=$'\033[0;31m'
_C_YELLOW=$'\033[1;33m'
_C_NC=$'\033[0m'

log()  { printf '%s[fpk-runner]%s %s\n' "$_C_GREEN" "$_C_NC" "$*" >&2; }
warn() { printf '%s[fpk-runner WARN]%s %s\n' "$_C_YELLOW" "$_C_NC" "$*" >&2; }
die()  { printf '%s[fpk-runner ERROR]%s %s\n' "$_C_RED" "$_C_NC" "$*" >&2; exit 1; }

load_state() {
    [ -f "$STATE_ENV" ] || die "no state — call 'install' first"
    # shellcheck disable=SC1090
    source "$STATE_ENV"
}

save_state() {
    cat > "$STATE_ENV" <<EOF
export TRIM_APPNAME='${TRIM_APPNAME:?}'
export TRIM_APPDEST='${TRIM_APPDEST:?}'
export TRIM_PKGVAR='${TRIM_PKGVAR:?}'
export TRIM_PKGETC='${TRIM_PKGETC:?}'
export TRIM_PKGHOME='${TRIM_PKGHOME:?}'
export TRIM_SERVICE_PORT='${TRIM_SERVICE_PORT:?}'
export TRIM_USERNAME='${TRIM_USERNAME:-fnostest}'
export TRIM_GROUPNAME='${TRIM_GROUPNAME:-fnostest}'
export TRIM_UID='${TRIM_UID:-10001}'
export TRIM_GID='${TRIM_GID:-10001}'
export TRIM_APP_STATUS='installed'
export TRIM_TEMP_LOGFILE='${TRIM_TEMP_LOGFILE}'
export DOCKER_MIRROR=''
export VERSION='${VERSION:-}'
export HEALTH_JSON='${HEALTH_JSON:-}'
EOF
}

manifest_value() {
    local manifest="$1" key="$2"
    awk -F= -v k="$key" '
        $1 ~ ("^"k"[[:space:]]*$") {
            sub(/^[[:space:]]+/, "", $2)
            sub(/[[:space:]]+$/, "", $2)
            print $2; exit
        }
    ' "$manifest"
}

cmd_install() {
    local fpk="${1:?install requires <fpk-path>}"
    [ -f "$fpk" ] || die "fpk not found: $fpk"

    log "Extracting $fpk"
    rm -rf "$EXTRACT_BASE"
    mkdir -p "$EXTRACT_BASE"
    tar -xzf "$fpk" -C "$EXTRACT_BASE" || die "fpk extract failed"

    local manifest="$EXTRACT_BASE/manifest"
    [ -f "$manifest" ] || die "fpk missing manifest"

    TRIM_APPNAME="$(manifest_value "$manifest" appname)"
    [ -n "$TRIM_APPNAME" ] || die "manifest.appname empty"
    TRIM_SERVICE_PORT="$(manifest_value "$manifest" service_port)"
    VERSION="$(manifest_value "$manifest" version)"

    TRIM_APPDEST="/usr/trim/apps/$TRIM_APPNAME"
    TRIM_PKGVAR="/vol1/$TRIM_APPNAME"
    TRIM_PKGETC="/var/apps/$TRIM_APPNAME/etc"
    TRIM_PKGHOME="/var/apps/$TRIM_APPNAME/home"
    TRIM_TEMP_LOGFILE="$STATE_DIR/install.log"

    mkdir -p "$TRIM_APPDEST" "$TRIM_PKGVAR" "$TRIM_PKGETC" "$TRIM_PKGHOME"
    : > "$TRIM_TEMP_LOGFILE"

    log "Extracting app.tgz to TRIM_APPDEST=$TRIM_APPDEST"
    [ -f "$EXTRACT_BASE/app.tgz" ] || die "fpk missing app.tgz"
    tar -xzf "$EXTRACT_BASE/app.tgz" -C "$TRIM_APPDEST" || die "app.tgz extract failed"

    # Copy a health.json into state so 'probe' can read it without going back to the source repo.
    if [ -f "$EXTRACT_BASE/health.json" ]; then
        cp "$EXTRACT_BASE/health.json" "$STATE_DIR/health.json"
        HEALTH_JSON="$STATE_DIR/health.json"
    elif [ -n "${HEALTH_JSON_SOURCE:-}" ] && [ -f "$HEALTH_JSON_SOURCE" ]; then
        cp "$HEALTH_JSON_SOURCE" "$STATE_DIR/health.json"
        HEALTH_JSON="$STATE_DIR/health.json"
    else
        HEALTH_JSON=""
    fi

    save_state
    # shellcheck disable=SC1090
    source "$STATE_ENV"

    log "Running cmd/install_init"
    bash "$EXTRACT_BASE/cmd/install_init" || die "install_init failed (exit $?)"

    log "Running cmd/install_callback"
    bash "$EXTRACT_BASE/cmd/install_callback" || die "install_callback failed (exit $?)"

    log "Install OK — appname=$TRIM_APPNAME version=$VERSION port=$TRIM_SERVICE_PORT"
}

cmd_start() {
    load_state
    local main="$EXTRACT_BASE/cmd/main"
    [ -x "$main" ] || die "cmd/main missing or not executable"
    log "Running cmd/main start"
    bash "$main" start || die "start exited non-zero"

    local pid_file="$TRIM_PKGVAR/$TRIM_APPNAME.pid"
    local deadline=$(( $(date +%s) + 10 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if [ -s "$pid_file" ]; then
            local pid
            pid="$(head -1 "$pid_file")"
            if kill -0 "$pid" 2>/dev/null; then
                log "Daemon PID=$pid alive after start"
                return 0
            fi
        fi
        sleep 1
    done
    warn "no live PID after 10s — daemon may have exited early (this is the most common 'install-then-unusable' signature)"
    return 1
}

probe_http() {
    local port="$1" path="$2" timeout="$3"
    local statuses="$4"
    local deadline=$(( $(date +%s) + timeout ))
    local last_code=""
    while [ "$(date +%s)" -lt "$deadline" ]; do
        last_code="$(curl -s -o /dev/null -w '%{http_code}' \
                     --max-time 5 \
                     "http://127.0.0.1:${port}${path}" || echo "000")"
        if echo "$statuses" | grep -qw "$last_code"; then
            log "HTTP $last_code from 127.0.0.1:${port}${path} (accepted)"
            return 0
        fi
        sleep 2
    done
    warn "HTTP probe failed — last code: '$last_code' (acceptable: $statuses)"
    return 1
}

probe_tcp() {
    local port="$1" timeout="$2"
    local deadline=$(( $(date +%s) + timeout ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if (echo > "/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
            log "TCP 127.0.0.1:$port accepts connections"
            return 0
        fi
        sleep 2
    done
    warn "TCP probe failed — nothing listening on 127.0.0.1:$port"
    return 1
}

cmd_probe() {
    load_state
    local hjson="${HEALTH_JSON:-}"
    local type="http" path="/" port="$TRIM_SERVICE_PORT" timeout=60 warmup=0
    local statuses="200 301 302 401 403"

    if [ -n "$hjson" ] && [ -f "$hjson" ]; then
        type="$(jq -r '.type // "http"' "$hjson")"
        path="$(jq -r '.path // "/"' "$hjson")"
        local p
        p="$(jq -r '.port // empty' "$hjson")"
        [ -n "$p" ] && port="$p"
        timeout="$(jq -r '.startup_timeout_seconds // 60' "$hjson")"
        warmup="$(jq -r '.post_install_warmup_seconds // 0' "$hjson")"
        local es
        es="$(jq -r '.expect_status // empty | if . == "" then "" else (. | join(" ")) end' "$hjson" 2>/dev/null || true)"
        [ -n "$es" ] && statuses="$es"
    fi

    if [ "$type" = "skip" ]; then
        log "health.type=skip — probe skipped"
        return 0
    fi

    if [ "$warmup" -gt 0 ]; then
        log "Warmup ${warmup}s before probing"
        sleep "$warmup"
    fi

    log "Probing type=$type port=$port path=$path timeout=${timeout}s"
    case "$type" in
        http) probe_http "$port" "$path" "$timeout" "$statuses" ;;
        tcp)  probe_tcp  "$port" "$timeout" ;;
        *)    die "unknown health.type='$type'" ;;
    esac
}

cmd_stop() {
    load_state
    local main="$EXTRACT_BASE/cmd/main"
    [ -x "$main" ] || die "cmd/main missing"
    log "Running cmd/main stop"
    bash "$main" stop || warn "stop returned non-zero"

    local pid_file="$TRIM_PKGVAR/$TRIM_APPNAME.pid"
    if [ -f "$pid_file" ]; then
        warn "PID file still present after stop: $pid_file"
        return 1
    fi
    log "Stop OK — PID file removed"
}

cmd_uninstall() {
    load_state
    log "Running cmd/uninstall_init"
    bash "$EXTRACT_BASE/cmd/uninstall_init" || warn "uninstall_init non-zero"

    export wizard_delete_data=true
    log "Running cmd/uninstall_callback (wizard_delete_data=true)"
    bash "$EXTRACT_BASE/cmd/uninstall_callback" || warn "uninstall_callback non-zero"
    log "Uninstall complete"
}

cmd_logs() {
    load_state
    local log_file="$TRIM_PKGVAR/$TRIM_APPNAME.log"
    if [ -f "$log_file" ]; then
        echo "===== $log_file ====="
        cat "$log_file"
    else
        warn "no log file at $log_file"
    fi
    local install_log="$STATE_DIR/install.log"
    if [ -f "$install_log" ] && [ -s "$install_log" ]; then
        echo "===== $install_log ====="
        cat "$install_log"
    fi
}

cmd_assert_clean() {
    load_state
    local rc=0
    local pid_file="$TRIM_PKGVAR/$TRIM_APPNAME.pid"
    if [ -f "$pid_file" ]; then
        warn "leftover PID file: $pid_file"
        rc=1
    fi
    if ss -lntp 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${TRIM_SERVICE_PORT}$"; then
        warn "port $TRIM_SERVICE_PORT still has a listener after stop"
        rc=1
    fi
    if pgrep -f "$TRIM_APPNAME" >/dev/null 2>&1; then
        local procs
        procs="$(pgrep -af "$TRIM_APPNAME" || true)"
        warn "processes matching '$TRIM_APPNAME' still running:"$'\n'"$procs"
        rc=1
    fi
    if [ "$rc" -eq 0 ]; then
        log "assert-clean: PASS"
    else
        warn "assert-clean: FAIL"
    fi
    return "$rc"
}

cmd_help() {
    sed -n '2,20p' "$0"
}

case "${1:-help}" in
    install)        shift; cmd_install "$@" ;;
    start)          cmd_start ;;
    probe)          cmd_probe ;;
    stop)           cmd_stop ;;
    uninstall)      cmd_uninstall ;;
    logs)           cmd_logs ;;
    assert-clean)   cmd_assert_clean ;;
    help|--help|-h) cmd_help ;;
    *)              die "unknown subcommand '$1' — try 'help'" ;;
esac
