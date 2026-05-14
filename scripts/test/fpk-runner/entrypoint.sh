#!/bin/bash
# fpk-runner — fnOS install-fpk simulator for L3 testing.
#
# Subcommands:
#   install <fpk-path>                Extract + run install_init + install_callback
#   start                             Run cmd/main start as the package user
#   probe                             HTTP/TCP probe per health.json
#   stop                              Run cmd/main stop as the package user
#   uninstall                         Run uninstall_init + uninstall_callback (with data delete)
#   logs                              Cat LOG_FILE for the installed app
#   assert-clean                      Assert no PID, no port, no leftover data
#   help                              Show this help
#
# Filesystem layout (per fnos-developer-guide, "fnOS 运行时路径" appendix):
#   /vol1/@appcenter/<app>          → TRIM_APPDEST   (app code, target/)
#   /vol1/@appdata/<app>            → TRIM_PKGVAR    (var/, runtime data)
#   /vol1/@appconf/<app>            → TRIM_PKGETC    (etc/, static config)
#   /vol1/@apphome/<app>            → TRIM_PKGHOME   (home/, user data)
#   /vol1/@apptemp/<app>            → TRIM_PKGTMP    (tmp/)
#   /var/apps/<app>/etc             → INST_ETC referenced by shared/cmd/common
#                                     (stores installer-variables; emptied on uninstall)
#
# Privilege model (per docs/fnos-developer-guide section 五):
#   config/privilege.run-as=package → service runs as configured username/groupname
#   config/privilege.run-as=root    → service runs as root (rare, enterprise only)
#   join-groups (alias: extra-groups) → additional supplementary groups
#
# State (per container):
#   /var/run/fpk-runner/env         → exports for subsequent subcommand calls
#   /var/run/fpk-runner/extracted/  → unpacked fpk root (manifest, cmd/, app.tgz…)
#   /var/run/fpk-runner/health.json → resolved health spec (if any)

set -euo pipefail

STATE_DIR=/var/run/fpk-runner
STATE_ENV="$STATE_DIR/env"
EXTRACT_BASE="$STATE_DIR/extracted"

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
    {
        printf 'export TRIM_APPNAME=%q\n'        "$TRIM_APPNAME"
        printf 'export TRIM_APPVER=%q\n'         "${TRIM_APPVER:-}"
        printf 'export TRIM_APPDEST=%q\n'        "$TRIM_APPDEST"
        printf 'export TRIM_PKGVAR=%q\n'         "$TRIM_PKGVAR"
        printf 'export TRIM_PKGETC=%q\n'         "$TRIM_PKGETC"
        printf 'export TRIM_PKGHOME=%q\n'        "$TRIM_PKGHOME"
        printf 'export TRIM_PKGTMP=%q\n'         "$TRIM_PKGTMP"
        printf 'export TRIM_SERVICE_PORT=%q\n'   "$TRIM_SERVICE_PORT"
        printf 'export TRIM_USERNAME=%q\n'       "$TRIM_USERNAME"
        printf 'export TRIM_GROUPNAME=%q\n'      "$TRIM_GROUPNAME"
        printf 'export TRIM_UID=%q\n'            "$TRIM_UID"
        printf 'export TRIM_GID=%q\n'            "$TRIM_GID"
        printf 'export TRIM_RUN_USERNAME=root\n'
        printf 'export TRIM_RUN_GROUPNAME=root\n'
        printf 'export TRIM_RUN_UID=0\n'
        printf 'export TRIM_RUN_GID=0\n'
        printf 'export TRIM_APP_STATUS=installed\n'
        printf 'export TRIM_TEMP_LOGFILE=%q\n'   "$TRIM_TEMP_LOGFILE"
        printf 'export DOCKER_MIRROR=\n'
        printf 'export VERSION=%q\n'             "${VERSION:-}"
        printf 'export HEALTH_JSON=%q\n'         "${HEALTH_JSON:-}"
        printf 'export RUN_AS=%q\n'              "$RUN_AS"
        printf 'export INST_ETC=%q\n'            "$INST_ETC"
    } > "$STATE_ENV"
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

parse_privilege() {
    local privilege_file="$1"
    local app_default="$2"

    PRIV_RUN_AS="package"
    PRIV_USERNAME="$app_default"
    PRIV_GROUPNAME="$app_default"
    PRIV_JOIN_GROUPS=()

    if [ ! -f "$privilege_file" ]; then
        warn "no config/privilege; defaulting to run-as=package user='$app_default'"
        return 0
    fi

    if ! jq -e . <"$privilege_file" >/dev/null 2>&1; then
        die "config/privilege is not valid JSON: $privilege_file"
    fi

    PRIV_RUN_AS="$(jq -r '.defaults["run-as"] // "package"' "$privilege_file")"
    PRIV_USERNAME="$(jq -r --arg d "$app_default" '.username // $d' "$privilege_file")"
    PRIV_GROUPNAME="$(jq -r --arg d "$app_default" '.groupname // $d' "$privilege_file")"

    local groups_json
    groups_json="$(jq -c '."join-groups" // ."extra-groups" // []' "$privilege_file")"
    while IFS= read -r g; do
        [ -n "$g" ] && PRIV_JOIN_GROUPS+=("$g")
    done < <(jq -r '.[]?' <<<"$groups_json")
}

ensure_group() {
    local name="$1"
    getent group "$name" >/dev/null 2>&1 || groupadd --system "$name"
}

ensure_user() {
    local username="$1" groupname="$2"
    ensure_group "$groupname"
    if ! getent passwd "$username" >/dev/null 2>&1; then
        useradd --system --no-create-home --shell /usr/sbin/nologin \
                --gid "$groupname" "$username"
    fi
    for g in "${PRIV_JOIN_GROUPS[@]}"; do
        ensure_group "$g"
        usermod -a -G "$g" "$username" 2>/dev/null || true
    done
}

ensure_layout() {
    mkdir -p "$TRIM_APPDEST" "$TRIM_PKGVAR" "$TRIM_PKGETC" \
             "$TRIM_PKGHOME" "$TRIM_PKGTMP" "$INST_ETC"
}

chown_app_dirs() {
    local owner="$TRIM_USERNAME:$TRIM_GROUPNAME"
    chown -R "$owner" "$TRIM_APPDEST" "$TRIM_PKGVAR" "$TRIM_PKGETC" \
                      "$TRIM_PKGHOME" "$TRIM_PKGTMP" "$INST_ETC"
}

run_as_package() {
    if [ "$RUN_AS" = "root" ]; then
        bash "$@"
    else
        sudo --preserve-env -u "$TRIM_USERNAME" -g "$TRIM_GROUPNAME" \
             env "PATH=$PATH" bash "$@"
    fi
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
    TRIM_APPVER="$(manifest_value "$manifest" version)"
    VERSION="$TRIM_APPVER"

    parse_privilege "$EXTRACT_BASE/config/privilege" "$TRIM_APPNAME"
    RUN_AS="$PRIV_RUN_AS"
    TRIM_USERNAME="$PRIV_USERNAME"
    TRIM_GROUPNAME="$PRIV_GROUPNAME"

    ensure_user "$TRIM_USERNAME" "$TRIM_GROUPNAME"
    TRIM_UID="$(id -u "$TRIM_USERNAME")"
    TRIM_GID="$(getent group "$TRIM_GROUPNAME" | cut -d: -f3)"

    TRIM_APPDEST="/vol1/@appcenter/$TRIM_APPNAME"
    TRIM_PKGVAR="/vol1/@appdata/$TRIM_APPNAME"
    TRIM_PKGETC="/vol1/@appconf/$TRIM_APPNAME"
    TRIM_PKGHOME="/vol1/@apphome/$TRIM_APPNAME"
    TRIM_PKGTMP="/vol1/@apptemp/$TRIM_APPNAME"
    INST_ETC="/var/apps/$TRIM_APPNAME/etc"
    TRIM_TEMP_LOGFILE="$STATE_DIR/install.log"

    ensure_layout
    : > "$TRIM_TEMP_LOGFILE"

    log "Extracting app.tgz to TRIM_APPDEST=$TRIM_APPDEST"
    [ -f "$EXTRACT_BASE/app.tgz" ] || die "fpk missing app.tgz"
    tar -xzf "$EXTRACT_BASE/app.tgz" -C "$TRIM_APPDEST" || die "app.tgz extract failed"

    chown_app_dirs

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

    log "Installed user=$TRIM_USERNAME($TRIM_UID) group=$TRIM_GROUPNAME($TRIM_GID) run-as=$RUN_AS"

    log "Running cmd/install_init (as root, matches fnOS)"
    bash "$EXTRACT_BASE/cmd/install_init" || die "install_init failed (exit $?)"

    log "Running cmd/install_callback (as root, matches fnOS)"
    bash "$EXTRACT_BASE/cmd/install_callback" || die "install_callback failed (exit $?)"

    chown_app_dirs

    log "Install OK — appname=$TRIM_APPNAME version=$VERSION port=$TRIM_SERVICE_PORT"
}

cmd_start() {
    load_state
    local main="$EXTRACT_BASE/cmd/main"
    [ -x "$main" ] || die "cmd/main missing or not executable"
    log "Running cmd/main start (as $TRIM_USERNAME)"
    run_as_package "$main" start || die "start exited non-zero"

    local pid_file="$TRIM_PKGVAR/$TRIM_APPNAME.pid"
    local deadline=$(( $(date +%s) + 10 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if [ -s "$pid_file" ]; then
            local pid
            pid="$(head -1 "$pid_file")"
            if kill -0 "$pid" 2>/dev/null; then
                local proc_user
                proc_user="$(stat -c '%U' /proc/"$pid" 2>/dev/null || echo '?')"
                log "Daemon PID=$pid alive after start (owner: $proc_user)"
                return 0
            fi
        fi
        sleep 1
    done
    warn "no live PID after 10s — daemon may have exited early (the typical 'install-then-unusable' signature)"
    return 1
}

probe_http() {
    local port="$1" path="$2" timeout="$3" statuses="$4"
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
    log "Running cmd/main stop (as $TRIM_USERNAME)"
    run_as_package "$main" stop || warn "stop returned non-zero"

    local pid_file="$TRIM_PKGVAR/$TRIM_APPNAME.pid"
    if [ -f "$pid_file" ]; then
        warn "PID file still present after stop: $pid_file"
        return 1
    fi
    log "Stop OK — PID file removed"
}

cmd_uninstall() {
    load_state
    log "Running cmd/uninstall_init (as root, matches fnOS)"
    bash "$EXTRACT_BASE/cmd/uninstall_init" || warn "uninstall_init non-zero"

    export wizard_delete_data=true
    log "Running cmd/uninstall_callback wizard_delete_data=true"
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

assert_dir_empty() {
    local dir="$1" label="$2"
    [ -d "$dir" ] || return 0
    local leftover
    leftover="$(find "$dir" -mindepth 1 -print 2>/dev/null | head -5 || true)"
    if [ -n "$leftover" ]; then
        warn "leftover files under $label ($dir):"$'\n'"$leftover"
        return 1
    fi
    return 0
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

    assert_dir_empty "$TRIM_PKGVAR"  "TRIM_PKGVAR"  || rc=1
    assert_dir_empty "$TRIM_PKGHOME" "TRIM_PKGHOME" || rc=1
    assert_dir_empty "$INST_ETC"     "INST_ETC (/var/apps/$TRIM_APPNAME/etc)" || rc=1

    if [ "$rc" -eq 0 ]; then
        log "assert-clean: PASS (no PID, no listener, no process, data dirs empty)"
    else
        warn "assert-clean: FAIL — see warnings above"
    fi
    return "$rc"
}

cmd_help() {
    sed -n '2,32p' "$0"
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
