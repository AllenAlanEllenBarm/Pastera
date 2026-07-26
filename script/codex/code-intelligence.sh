#!/bin/sh

set -eu

UV_VERSION=0.11.31
PYTHON_VERSION=3.12
CGC_VERSION=0.5.1

error() {
    printf 'code-intelligence: %s\n' "$*" >&2
}

die() {
    error "$@"
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        die "sha256sum or shasum is required"
    fi
}

sha256_stream() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}'
    else
        die "sha256sum or shasum is required"
    fi
}

sha256_index_environment() {
    # Response size changes do not affect graph contents. Normalize the original
    # committed value so tightening this budget does not rotate an existing DB.
    sed \
        -e 's/^MAX_TOOL_RESPONSE_TOKENS=.*/MAX_TOOL_RESPONSE_TOKENS=2500/' \
        -e "s/^TOOL_RESULT_LIMITS=.*/TOOL_RESULT_LIMITS='{\"find_code\":12,\"analyze_code_relationships\":8}'/" \
        "$CGC_ENV_FILE" | sha256_stream
}

canonical_directory() {
    test -d "$1" || die "directory does not exist: $1"
    (cd "$1" && pwd -P)
}

require_command git
SCRIPT_DIR=$(canonical_directory "$(dirname "$0")")
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null) || die "script is not inside a Git worktree"
REPO_ROOT=$(canonical_directory "$REPO_ROOT")
GIT_COMMON_RAW=$(git -C "$REPO_ROOT" rev-parse --git-common-dir)
case "$GIT_COMMON_RAW" in
    /*) GIT_COMMON=$(canonical_directory "$GIT_COMMON_RAW") ;;
    *) GIT_COMMON=$(canonical_directory "$REPO_ROOT/$GIT_COMMON_RAW") ;;
esac

TOOLS_DIR="$REPO_ROOT/tools/code-intelligence"
LOCK_FILE="$TOOLS_DIR/uv.lock"
CHECKSUM_FILE="$TOOLS_DIR/checksums.txt"
CGC_DIR="$REPO_ROOT/.codegraphcontext"
CGC_ENV_FILE="$CGC_DIR/.env"
CGC_IGNORE_FILE="$REPO_ROOT/.cgcignore"
RUNTIME_ROOT="$GIT_COMMON/codex-code-intelligence"
UV_BIN="$RUNTIME_ROOT/bin/uv"
VENV_DIR="$RUNTIME_ROOT/venv"
CGC_BIN="$VENV_DIR/bin/cgc"
RUNTIME_STAMP="$RUNTIME_ROOT/uv.lock.sha256"
INSTALL_LOCK="$RUNTIME_ROOT/install.lock.d"
STATE_DIR="$CGC_DIR/runtime"
PID_FILE="$STATE_DIR/watcher.pid"
READY_FILE="$STATE_DIR/watcher.ready"
GENERATION_FILE="$STATE_DIR/generation"
WATCHER_LOG="$STATE_DIR/watcher.log"
WATCHER_LOCK="$STATE_DIR/watcher.lock.d"

require_project_files() {
    for required_file in "$LOCK_FILE" "$CGC_ENV_FILE" "$CGC_DIR/config.yaml" "$CGC_IGNORE_FILE"; do
        test -f "$required_file" || die "required project file is missing: $required_file"
    done
}

read_generation() {
    if test ! -f "$GENERATION_FILE"; then
        printf '%s\n' 0
        return
    fi
    generation=$(sed -n '1p' "$GENERATION_FILE")
    case "$generation" in
        ''|*[!0-9]*) die "invalid database generation in $GENERATION_FILE" ;;
        *) printf '%s\n' "$generation" ;;
    esac
}

refresh_derived_paths() {
    require_project_files
    GENERATION=$(read_generation)
    WORKTREE_HASH=$(printf '%s' "$REPO_ROOT" | sha256_stream | cut -c1-12)
    CONFIG_FINGERPRINT=$(
        {
            sha256_file "$LOCK_FILE"
            sha256_index_environment
            sha256_file "$CGC_DIR/config.yaml"
            sha256_file "$CGC_IGNORE_FILE"
            printf '%s\n' "$GENERATION"
        } | sha256_stream | cut -c1-16
    )
    DB_DIR="$CGC_DIR/db/$CONFIG_FINGERPRINT"
    DB_PATH="$DB_DIR/falkordb.db"
    KUZU_FALLBACK_PATH="$DB_DIR/kuzudb"
    RUNTIME_DB_LINK="/tmp/cgc-$(id -u)-$WORKTREE_HASH-$CONFIG_FINGERPRINT"
    RUNTIME_DB_PATH="$RUNTIME_DB_LINK/falkordb.db"
    SOCKET_PATH="$RUNTIME_DB_LINK/falkordb.sock"
    test "${#SOCKET_PATH}" -lt 100 \
        || die "derived FalkorDB socket path is too long: $SOCKET_PATH"
}

prepare_falkordb_runtime_path() {
    mkdir -p "$DB_DIR"
    if test -L "$RUNTIME_DB_LINK"; then
        linked_db_dir=$(readlink "$RUNTIME_DB_LINK")
        test "$linked_db_dir" = "$DB_DIR" \
            || die "runtime database link points to an unexpected directory: $RUNTIME_DB_LINK -> $linked_db_dir"
        return
    fi
    test ! -e "$RUNTIME_DB_LINK" \
        || die "runtime database path exists and is not a symbolic link: $RUNTIME_DB_LINK"
    ln -s "$DB_DIR" "$RUNTIME_DB_LINK"
}

kuzu_fallback_exists() {
    test -e "$KUZU_FALLBACK_PATH" || test -e "$KUZU_FALLBACK_PATH.wal"
}

acquire_lock() {
    lock_path=$1
    timeout_seconds=$2
    waited=0
    while ! mkdir "$lock_path" 2>/dev/null; do
        owner=
        if test -f "$lock_path/owner"; then
            owner=$(sed -n '1p' "$lock_path/owner")
        fi
        case "$owner" in
            ''|*[!0-9]*)
                if test "$waited" -ge 2; then
                    rm -f "$lock_path/owner"
                    rmdir "$lock_path" 2>/dev/null || true
                fi
                ;;
            *)
                if ! kill -0 "$owner" 2>/dev/null; then
                    rm -f "$lock_path/owner"
                    rmdir "$lock_path" 2>/dev/null || true
                fi
                ;;
        esac
        waited=$((waited + 1))
        test "$waited" -lt "$timeout_seconds" || die "timed out waiting for lock: $lock_path"
        sleep 1
    done
    printf '%s\n' "$$" >"$lock_path/owner"
}

release_lock() {
    lock_path=$1
    rm -f "$lock_path/owner"
    rmdir "$lock_path" 2>/dev/null || true
}

uv_asset_name() {
    system_name=$(uname -s)
    machine_name=$(uname -m)
    case "$system_name:$machine_name" in
        Darwin:arm64) printf '%s\n' "uv-aarch64-apple-darwin.tar.gz" ;;
        Darwin:x86_64) printf '%s\n' "uv-x86_64-apple-darwin.tar.gz" ;;
        Linux:aarch64|Linux:arm64) printf '%s\n' "uv-aarch64-unknown-linux-gnu.tar.gz" ;;
        Linux:x86_64|Linux:amd64) printf '%s\n' "uv-x86_64-unknown-linux-gnu.tar.gz" ;;
        *) die "unsupported platform: $system_name $machine_name" ;;
    esac
}

uv_is_pinned() {
    test -x "$UV_BIN" || return 1
    installed_uv_version=$("$UV_BIN" --version 2>/dev/null) || return 1
    case "$installed_uv_version" in
        "uv $UV_VERSION"|"uv $UV_VERSION "*) return 0 ;;
        *) return 1 ;;
    esac
}

cgc_is_pinned() {
    test -x "$CGC_BIN" || return 1
    installed_cgc_version=$("$CGC_BIN" --version 2>&1 | awk 'NR == 1 { print $NF }') \
        || return 1
    test "$installed_cgc_version" = "$CGC_VERSION"
}

install_uv() {
    if uv_is_pinned; then
        return
    fi

    require_command curl
    require_command tar
    test -f "$CHECKSUM_FILE" || die "checksum file is missing: $CHECKSUM_FILE"
    mkdir -p "$RUNTIME_ROOT/bin"
    asset_name=$(uv_asset_name)
    expected_checksum=$(awk -v asset="$asset_name" '$2 == asset { print $1 }' "$CHECKSUM_FILE")
    test -n "$expected_checksum" || die "checksum is missing for $asset_name"
    temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/pastera-code-intelligence.XXXXXX")
    archive_path="$temporary_dir/$asset_name"

    if ! curl -fsSL --show-error --retry 3 --connect-timeout 15 \
        "https://github.com/astral-sh/uv/releases/download/$UV_VERSION/$asset_name" \
        -o "$archive_path"; then
        rm -rf "$temporary_dir"
        die "failed to download uv $UV_VERSION"
    fi
    actual_checksum=$(sha256_file "$archive_path")
    if test "$actual_checksum" != "$expected_checksum"; then
        rm -rf "$temporary_dir"
        die "checksum mismatch for $asset_name"
    fi

    tar -xzf "$archive_path" -C "$temporary_dir"
    extracted_uv=$(find "$temporary_dir" -type f -name uv -perm -u+x -print | sed -n '1p')
    test -n "$extracted_uv" || {
        rm -rf "$temporary_dir"
        die "uv executable was not found in $asset_name"
    }
    mv "$extracted_uv" "$UV_BIN"
    chmod 0755 "$UV_BIN"
    rm -rf "$temporary_dir"
    uv_is_pinned || die "installed uv version is not $UV_VERSION"
}

sync_runtime_locked() (
    mkdir -p "$RUNTIME_ROOT"
    acquire_lock "$INSTALL_LOCK" 600
    trap 'release_lock "$INSTALL_LOCK"' EXIT HUP INT TERM

    lock_hash=$(sha256_file "$LOCK_FILE")
    installed_hash=
    if test -f "$RUNTIME_STAMP"; then
        installed_hash=$(sed -n '1p' "$RUNTIME_STAMP")
    fi
    if test "$installed_hash" = "$lock_hash" && cgc_is_pinned; then
        exit 0
    fi

    install_uv
    export UV_CACHE_DIR="$RUNTIME_ROOT/cache"
    export UV_PYTHON_INSTALL_DIR="$RUNTIME_ROOT/python"
    export UV_PROJECT_ENVIRONMENT="$VENV_DIR"
    "$UV_BIN" python install --no-bin "$PYTHON_VERSION"
    "$UV_BIN" sync --frozen --project "$TOOLS_DIR" --python "$PYTHON_VERSION"
    cgc_is_pinned || die "installed CodeGraphContext version is not $CGC_VERSION"
    temporary_stamp="$RUNTIME_STAMP.$$"
    printf '%s\n' "$lock_hash" >"$temporary_stamp"
    mv "$temporary_stamp" "$RUNTIME_STAMP"
)

require_runtime() {
    test -x "$CGC_BIN" || die "runtime is missing; run: script/codex/code-intelligence.sh bootstrap"
}

ensure_runtime_current() {
    require_project_files
    require_runtime
    lock_hash=$(sha256_file "$LOCK_FILE")
    installed_hash=
    if test -f "$RUNTIME_STAMP"; then
        installed_hash=$(sed -n '1p' "$RUNTIME_STAMP")
    fi
    if test "$installed_hash" != "$lock_hash"; then
        test -x "$UV_BIN" || die "runtime is stale and pinned uv is missing; run bootstrap"
        sync_runtime_locked
    fi
}

load_cgc_environment() {
    # The file is tracked project configuration and contains only fixed,
    # non-secret assignments reviewed with this script.
    set -a
    # shellcheck disable=SC1090
    . "$CGC_ENV_FILE"
    set +a
    export CGC_LOAD_PROJECT_ENV=1
    export CGC_RUNTIME_DB_TYPE=falkordb
    export CGC_RUNTIME_DB_PATH="$RUNTIME_DB_PATH"
    export FALKORDB_PATH="$RUNTIME_DB_PATH"
    export FALKORDB_SOCKET_PATH="$SOCKET_PATH"
    # Embedded FalkorDB is shared only through its per-worktree Unix socket.
    # Port 0 disables Redis TCP listening and avoids cross-worktree port 6379 conflicts.
    export FALKORDB_PORT=0
}

watcher_command_line() {
    watcher_pid=$1
    if test -r "/proc/$watcher_pid/cmdline"; then
        tr '\000' ' ' <"/proc/$watcher_pid/cmdline"
    else
        ps -p "$watcher_pid" -o command= 2>/dev/null || true
    fi
}

watcher_is_managed() {
    watcher_pid=$1
    command_line=$(watcher_command_line "$watcher_pid")
    case "$command_line" in
        *"$CGC_BIN"*"watch"*"$REPO_ROOT"*) return 0 ;;
        *) return 1 ;;
    esac
}

read_watcher_pid() {
    test -f "$PID_FILE" || return 1
    watcher_pid=$(sed -n '1p' "$PID_FILE")
    case "$watcher_pid" in
        ''|*[!0-9]*) return 1 ;;
        *) printf '%s\n' "$watcher_pid" ;;
    esac
}

stop_watcher_locked() {
    if ! watcher_pid=$(read_watcher_pid); then
        rm -f "$PID_FILE" "$READY_FILE"
        return 0
    fi
    if ! kill -0 "$watcher_pid" 2>/dev/null; then
        rm -f "$PID_FILE" "$READY_FILE"
        return 0
    fi
    if ! watcher_is_managed "$watcher_pid"; then
        error "refusing to stop PID $watcher_pid because it is not the managed watcher for $REPO_ROOT"
        return 1
    fi

    kill -TERM "$watcher_pid"
    waited=0
    while kill -0 "$watcher_pid" 2>/dev/null && test "$waited" -lt 5; do
        sleep 1
        waited=$((waited + 1))
    done
    if kill -0 "$watcher_pid" 2>/dev/null; then
        error "watcher PID $watcher_pid did not stop after 5 seconds"
        return 1
    fi
    rm -f "$PID_FILE" "$READY_FILE"
}

ensure_watcher_locked() (
    require_runtime
    refresh_derived_paths
    timeout_seconds=${CODE_INTELLIGENCE_WATCHER_TIMEOUT:-600}
    case "$timeout_seconds" in
        ''|*[!0-9]*) die "CODE_INTELLIGENCE_WATCHER_TIMEOUT must be an integer" ;;
    esac
    mkdir -p "$STATE_DIR" "$DB_DIR"
    acquire_lock "$WATCHER_LOCK" "$timeout_seconds"
    trap 'release_lock "$WATCHER_LOCK"' EXIT HUP INT TERM
    prepare_falkordb_runtime_path

    if kuzu_fallback_exists; then
        if watcher_pid=$(read_watcher_pid) \
            && kill -0 "$watcher_pid" 2>/dev/null \
            && watcher_is_managed "$watcher_pid"; then
            stop_watcher_locked
        fi
        die "unexpected KuzuDB fallback detected at $KUZU_FALLBACK_PATH; run reindex-codegraph after the FalkorDB cause is resolved"
    fi

    start_watcher=true
    if watcher_pid=$(read_watcher_pid); then
        if kill -0 "$watcher_pid" 2>/dev/null; then
            if ! watcher_is_managed "$watcher_pid"; then
                die "watcher PID file points to an unrelated process: $watcher_pid"
            fi
            ready_fingerprint=
            if test -f "$READY_FILE"; then
                ready_fingerprint=$(sed -n '1p' "$READY_FILE")
            fi
            if test "$ready_fingerprint" = "$CONFIG_FINGERPRINT"; then
                exit 0
            fi
            if test -z "$ready_fingerprint"; then
                start_watcher=false
            else
                stop_watcher_locked
            fi
        else
            rm -f "$PID_FILE" "$READY_FILE"
        fi
    fi

    if test "$start_watcher" = true; then
        : >"$WATCHER_LOG"
        load_cgc_environment
        (
            cd "$REPO_ROOT"
            nohup "$CGC_BIN" watch "$REPO_ROOT" </dev/null >>"$WATCHER_LOG" 2>&1 &
            printf '%s\n' "$!" >"$PID_FILE.tmp"
            mv "$PID_FILE.tmp" "$PID_FILE"
        )
        watcher_pid=$(read_watcher_pid) || die "watcher PID was not recorded"
    fi

    waited=0
    while test "$waited" -lt "$timeout_seconds"; do
        if kuzu_fallback_exists; then
            stop_watcher_locked
            die "CodeGraphContext fell back to KuzuDB at $KUZU_FALLBACK_PATH; refusing to mark the graph ready"
        fi
        if ! kill -0 "$watcher_pid" 2>/dev/null; then
            error "watcher exited before becoming ready; log: $WATCHER_LOG"
            sed -n '1,160p' "$WATCHER_LOG" >&2
            return 1
        fi
        if grep -q 'Monitoring for file changes' "$WATCHER_LOG"; then
            if kuzu_fallback_exists; then
                stop_watcher_locked
                die "CodeGraphContext fell back to KuzuDB at $KUZU_FALLBACK_PATH; refusing to mark the graph ready"
            fi
            printf '%s\n' "$CONFIG_FINGERPRINT" >"$READY_FILE.tmp"
            mv "$READY_FILE.tmp" "$READY_FILE"
            exit 0
        fi
        sleep 1
        waited=$((waited + 1))
    done

    error "watcher did not become ready within $timeout_seconds seconds; log: $WATCHER_LOG"
    return 1
)

ensure_watcher() {
    ensure_watcher_locked
}

stop_watcher() (
    mkdir -p "$STATE_DIR"
    acquire_lock "$WATCHER_LOCK" 30
    trap 'release_lock "$WATCHER_LOCK"' EXIT HUP INT TERM
    stop_watcher_locked
)

status_command() {
    refresh_derived_paths
    printf 'repo=%s\n' "$REPO_ROOT"
    if test -x "$CGC_BIN"; then
        printf 'runtime=ready\n'
    else
        printf 'runtime=missing\n'
    fi
    if watcher_pid=$(read_watcher_pid) \
        && kill -0 "$watcher_pid" 2>/dev/null \
        && watcher_is_managed "$watcher_pid"; then
        printf 'watcher=running\n'
        printf 'watcher_pid=%s\n' "$watcher_pid"
    else
        printf 'watcher=stopped\n'
    fi
    printf 'generation=%s\n' "$GENERATION"
    printf 'fingerprint=%s\n' "$CONFIG_FINGERPRINT"
    printf 'database=%s\n' "$DB_PATH"
    printf 'runtime_database=%s\n' "$RUNTIME_DB_PATH"
    printf 'socket=%s\n' "$SOCKET_PATH"
    if kuzu_fallback_exists; then
        printf 'backend=unexpected-kuzudb\n'
    elif test -S "$SOCKET_PATH"; then
        printf 'backend=falkordb\n'
    else
        printf 'backend=initializing\n'
    fi
}

doctor_command() {
    failures=0
    printf 'repository: %s\n' "$REPO_ROOT"
    if test -x "$UV_BIN"; then
        printf 'uv: %s\n' "$("$UV_BIN" --version 2>&1)"
    else
        printf 'uv: missing\n'
        failures=$((failures + 1))
    fi
    if test -x "$VENV_DIR/bin/python"; then
        printf 'python: %s\n' "$("$VENV_DIR/bin/python" --version 2>&1)"
    else
        printf 'python: missing\n'
        failures=$((failures + 1))
    fi
    if test -x "$CGC_BIN"; then
        printf 'codegraphcontext: %s\n' "$("$CGC_BIN" --version 2>&1)"
    else
        printf 'codegraphcontext: missing\n'
        failures=$((failures + 1))
    fi
    global_context_file="$HOME/.codegraphcontext/config.yaml"
    context_mode=
    if test -f "$global_context_file"; then
        context_mode=$(sed -n 's/^mode:[[:space:]]*//p' "$global_context_file" | sed -n '1p')
    fi
    if test "$context_mode" = "per-repo"; then
        printf 'context_mode=per-repo\n'
    else
        printf 'context_mode=%s\n' "${context_mode:-missing}"
        failures=$((failures + 1))
    fi
    if codex_mcp_configured; then
        printf 'codex_mcp=configured\n'
    else
        printf 'codex_mcp=missing\n'
        failures=$((failures + 1))
    fi
    status_command
    test "$failures" -eq 0
}

ensure_per_repo_mode() {
    global_context_file="$HOME/.codegraphcontext/config.yaml"
    context_mode=
    if test -f "$global_context_file"; then
        context_mode=$(sed -n 's/^mode:[[:space:]]*//p' "$global_context_file" | sed -n '1p')
    fi
    case "$context_mode" in
        per-repo) return ;;
        '')
            "$CGC_BIN" context mode per-repo
            ;;
        *)
            die "CodeGraphContext global mode is '$context_mode'; refusing to replace it. Review $global_context_file and switch explicitly with: $CGC_BIN context mode per-repo"
            ;;
    esac
}

codex_mcp_configured() {
    config_file="$REPO_ROOT/.codex/config.toml"
    test -f "$config_file" && grep -q '^\[mcp_servers\.pastera_codegraph\]$' "$config_file"
}

activate_codex_command() {
    config_dir="$REPO_ROOT/.codex"
    config_file="$config_dir/config.toml"
    mkdir -p "$config_dir"

    if codex_mcp_configured; then
        printf '%s\n' "Codex MCP already configured in $config_file"
        return
    fi
    if test -f "$config_file" && grep -q 'pastera_codegraph' "$config_file"; then
        die "found an unrecognized pastera_codegraph entry in $config_file; review it before retrying"
    fi

    {
        if test -s "$config_file"; then
            printf '\n'
        fi
        printf '%s\n' \
            '[mcp_servers.pastera_codegraph]' \
            'command = "/bin/sh"' \
            'args = ["script/codex/code-intelligence.sh", "mcp-codegraph"]' \
            'cwd = ".."' \
            'required = false' \
            'startup_timeout_sec = 600' \
            'tool_timeout_sec = 120' \
            'enabled_tools = [' \
            '  "find_code",' \
            '  "analyze_code_relationships",' \
            ']'
    } >>"$config_file"
    printf '%s\n' "Added the Pastera CodeGraph MCP to $config_file"
}

bootstrap_command() {
    case "${1:-}" in
        ''|--non-interactive) ;;
        *) die "unsupported bootstrap option: $1" ;;
    esac
    require_project_files
    activate_codex_command
    mkdir -p "$RUNTIME_ROOT"
    install_uv
    sync_runtime_locked
    ensure_per_repo_mode
    if test -z "${CODE_INTELLIGENCE_WATCHER_TIMEOUT:-}"; then
        CODE_INTELLIGENCE_WATCHER_TIMEOUT=1800
        export CODE_INTELLIGENCE_WATCHER_TIMEOUT
    fi
    ensure_watcher
    doctor_command
    printf '%s\n' 'bootstrap complete; start a new Codex task and inspect /mcp'
}

reindex_command() {
    stop_watcher
    mkdir -p "$STATE_DIR"
    current_generation=$(read_generation)
    next_generation=$((current_generation + 1))
    printf '%s\n' "$next_generation" >"$GENERATION_FILE.tmp"
    mv "$GENERATION_FILE.tmp" "$GENERATION_FILE"
    ensure_watcher
}

mcp_command() {
    ensure_runtime_current
    ensure_watcher
    refresh_derived_paths
    load_cgc_environment
    cd "$REPO_ROOT"
    exec "$VENV_DIR/bin/python" "$TOOLS_DIR/mcp_server.py"
}

usage() {
    printf '%s\n' \
        'usage: script/codex/code-intelligence.sh <command>' \
        'commands:' \
        '  bootstrap [--non-interactive]' \
        '  activate-codex' \
        '  doctor' \
        '  status' \
        '  ensure-codegraph-watcher' \
        '  stop-codegraph-watcher' \
        '  reindex-codegraph' \
        '  mcp-codegraph'
}

command_name=${1:-}
if test "$#" -gt 0; then
    shift
fi
case "$command_name" in
    bootstrap) bootstrap_command "${1:-}" ;;
    activate-codex) activate_codex_command ;;
    doctor) doctor_command ;;
    status) status_command ;;
    ensure-codegraph-watcher) ensure_watcher ;;
    stop-codegraph-watcher) stop_watcher ;;
    reindex-codegraph) reindex_command ;;
    mcp-codegraph) mcp_command ;;
    -h|--help|help) usage ;;
    '') usage; exit 1 ;;
    *) usage >&2; die "unknown command: $command_name" ;;
esac
