#!/bin/sh

set -eu

PROJECT_ROOT=$(cd "$(dirname "$0")/../../.." && pwd -P)
SCRIPT_PATH="$PROJECT_ROOT/script/codex/code-intelligence.sh"
FAILURES=0
TESTS=0
FIXTURE_ROOT=
INNOCENT_PID=

cleanup() {
    if test -n "$INNOCENT_PID" && kill -0 "$INNOCENT_PID" 2>/dev/null; then
        kill "$INNOCENT_PID" 2>/dev/null || true
    fi
    if test -n "$FIXTURE_ROOT" && test -d "$FIXTURE_ROOT"; then
        fixture_script="$FIXTURE_ROOT/script/codex/code-intelligence.sh"
        if test -x "$fixture_script"; then
            "$fixture_script" stop-codegraph-watcher >/dev/null 2>&1 || true
        fi
        rm -rf "$FIXTURE_ROOT"
    fi
}

trap cleanup EXIT HUP INT TERM

pass() {
    TESTS=$((TESTS + 1))
    printf 'ok %s - %s\n' "$TESTS" "$1"
}

fail() {
    TESTS=$((TESTS + 1))
    FAILURES=$((FAILURES + 1))
    printf 'not ok %s - %s\n' "$TESTS" "$1"
}

assert_contains() {
    haystack=$1
    needle=$2
    case "$haystack" in
        *"$needle"*) return 0 ;;
        *) return 1 ;;
    esac
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

test_project_contract() {
    if ! test -x "$SCRIPT_PATH"; then
        fail "public script exists and is executable"
        return
    fi
    pass "public script exists and is executable"

    if test -f "$PROJECT_ROOT/tools/code-intelligence/mcp_server.py" \
        && grep -q 'CGC_RUNTIME_DB_PATH' "$PROJECT_ROOT/tools/code-intelligence/mcp_server.py" \
        && grep -q 'get_backend_type' "$PROJECT_ROOT/tools/code-intelligence/mcp_server.py" \
        && grep -q 'class ProjectMCPServer' "$PROJECT_ROOT/tools/code-intelligence/mcp_server.py" \
        && grep -q 'def _project_relative_path' "$PROJECT_ROOT/tools/code-intelligence/mcp_server.py" \
        && grep -q 'def _diverse_relationship_slice' "$PROJECT_ROOT/tools/code-intelligence/mcp_server.py"; then
        pass "project MCP entrypoint preserves runtime identity and compacts results"
    else
        fail "project MCP entrypoint preserves runtime identity and compacts results"
    fi

    if test -f "$PROJECT_ROOT/.codex/config.toml" \
        && test "$(grep -c '^\[mcp_servers\.pastera_codegraph\]$' "$PROJECT_ROOT/.codex/config.toml")" -eq 1 \
        && grep -q '"find_code"' "$PROJECT_ROOT/.codex/config.toml" \
        && grep -q '"analyze_code_relationships"' "$PROJECT_ROOT/.codex/config.toml"; then
        pass "local project config exposes the Pastera CodeGraph MCP"
    else
        fail "local project config exposes the Pastera CodeGraph MCP"
    fi

    if test -f "$PROJECT_ROOT/tools/code-intelligence/pyproject.toml" \
        && grep -q 'codegraphcontext\[falkordb-embedded\].*0\.5\.1' "$PROJECT_ROOT/tools/code-intelligence/pyproject.toml" \
        && ! grep -qi 'serena' "$PROJECT_ROOT/tools/code-intelligence/pyproject.toml"; then
        pass "runtime dependency set is CodeGraph-only"
    else
        fail "runtime dependency set is CodeGraph-only"
    fi

    if test -f "$PROJECT_ROOT/.codegraphcontext/.env" \
        && grep -q '^database: falkordb$' "$PROJECT_ROOT/.codegraphcontext/config.yaml" \
        && grep -q '^ENABLE_AUTO_WATCH=false$' "$PROJECT_ROOT/.codegraphcontext/.env" \
        && grep -q '^MAX_TOOL_RESPONSE_TOKENS=1200$' "$PROJECT_ROOT/.codegraphcontext/.env" \
        && grep -q "^TOOL_RESULT_LIMITS='{\"find_code\":6,\"analyze_code_relationships\":6}'$" "$PROJECT_ROOT/.codegraphcontext/.env"; then
        pass "CodeGraph configuration enforces watcher and output limits"
    else
        fail "CodeGraph configuration enforces watcher and output limits"
    fi
}

test_output_budget_does_not_rotate_database() {
    create_fixture
    fixture_script="$FIXTURE_ROOT/script/codex/code-intelligence.sh"
    first_fingerprint=$("$fixture_script" status | sed -n 's/^fingerprint=//p')
    sed \
        -e 's/^MAX_TOOL_RESPONSE_TOKENS=.*/MAX_TOOL_RESPONSE_TOKENS=999/' \
        -e 's/^TOOL_RESULT_LIMITS=.*/TOOL_RESULT_LIMITS='"'"'{"find_code":2,"analyze_code_relationships":2}'"'"'/' \
        "$FIXTURE_ROOT/.codegraphcontext/.env" \
        >"$FIXTURE_ROOT/.codegraphcontext/.env.tmp"
    mv "$FIXTURE_ROOT/.codegraphcontext/.env.tmp" "$FIXTURE_ROOT/.codegraphcontext/.env"
    second_fingerprint=$("$fixture_script" status | sed -n 's/^fingerprint=//p')

    if test "$first_fingerprint" = "$second_fingerprint"; then
        pass "response token budget does not rotate the code graph database"
    else
        fail "response token budget does not rotate the code graph database"
    fi
}

test_missing_runtime_status() {
    if ! test -x "$SCRIPT_PATH"; then
        fail "status reports a missing runtime without failing"
        return
    fi

    create_fixture
    rm -rf "$FIXTURE_ROOT/.git/codex-code-intelligence"
    status_output=$("$FIXTURE_ROOT/script/codex/code-intelligence.sh" status 2>&1) || {
        fail "status reports a missing runtime without failing"
        return
    }
    if assert_contains "$status_output" "runtime=missing" \
        && assert_contains "$status_output" "watcher=stopped"; then
        pass "status reports a missing runtime without failing"
    else
        printf '%s\n' "$status_output"
        fail "status reports a missing runtime without failing"
    fi
}

create_fixture() {
    if test -n "$FIXTURE_ROOT" && test -d "$FIXTURE_ROOT"; then
        old_fixture_script="$FIXTURE_ROOT/script/codex/code-intelligence.sh"
        if test -x "$old_fixture_script"; then
            "$old_fixture_script" stop-codegraph-watcher >/dev/null 2>&1 || true
        fi
        rm -rf "$FIXTURE_ROOT"
    fi
    FIXTURE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/code intelligence test.XXXXXX")
    FIXTURE_ROOT=$(cd "$FIXTURE_ROOT" && pwd -P)
    git -C "$FIXTURE_ROOT" init -q
    mkdir -p \
        "$FIXTURE_ROOT/script/codex" \
        "$FIXTURE_ROOT/tools/code-intelligence" \
        "$FIXTURE_ROOT/.codegraphcontext" \
        "$FIXTURE_ROOT/pastera/Sources"
    cp "$SCRIPT_PATH" "$FIXTURE_ROOT/script/codex/code-intelligence.sh"
    if test -f "$PROJECT_ROOT/tools/code-intelligence/mcp_server.py"; then
        cp "$PROJECT_ROOT/tools/code-intelligence/mcp_server.py" \
            "$FIXTURE_ROOT/tools/code-intelligence/mcp_server.py"
    fi
    cp "$PROJECT_ROOT/tools/code-intelligence/uv.lock" "$FIXTURE_ROOT/tools/code-intelligence/uv.lock"
    cp "$PROJECT_ROOT/.codegraphcontext/.env" "$FIXTURE_ROOT/.codegraphcontext/.env"
    cp "$PROJECT_ROOT/.codegraphcontext/config.yaml" "$FIXTURE_ROOT/.codegraphcontext/config.yaml"
    cp "$PROJECT_ROOT/.cgcignore" "$FIXTURE_ROOT/.cgcignore"
    printf '%s\n' 'final class Demo {}' \
        >"$FIXTURE_ROOT/pastera/Sources/Demo.swift"

    runtime_root="$FIXTURE_ROOT/.git/codex-code-intelligence"
    mkdir -p "$runtime_root/venv/bin" "$runtime_root/bin"
    cat >"$runtime_root/venv/bin/cgc" <<'EOF'
#!/bin/sh
set -eu
case "${1:-}" in
    --version)
        printf '%s\n' 'CodeGraphContext 0.5.1' >&2
        ;;
    watch)
        test "${FALKORDB_PORT:-}" = "0"
        if test "${FAKE_CGC_CREATE_KUZU:-false}" = "true"; then
            : >"$(dirname "${CGC_RUNTIME_DB_PATH:?}")/kuzudb"
        fi
        ready_delay=${FAKE_CGC_READY_DELAY:-0}
        if test "$ready_delay" -gt 0; then
            sleep "$ready_delay"
        fi
        printf '%s\n' 'Monitoring for file changes...'
        trap 'exit 0' TERM INT
        while :; do
            sleep 1
        done
        ;;
    mcp)
        printf '%s\n' 'the project wrapper must not invoke cgc mcp directly' >&2
        exit 4
        ;;
    *)
        printf 'unexpected fake cgc arguments: %s\n' "$*" >&2
        exit 2
        ;;
esac
EOF
    chmod +x "$runtime_root/venv/bin/cgc"
    cat >"$runtime_root/venv/bin/python" <<'EOF'
#!/bin/sh
set -eu
case "${1:-}" in
    */tools/code-intelligence/mcp_server.py)
        runtime_db_dir=$(dirname "${FALKORDB_PATH:?}")
        test -L "$runtime_db_dir"
        persistent_db_dir=$(readlink "$runtime_db_dir")
        test "$CGC_RUNTIME_DB_PATH" = "$FALKORDB_PATH"
        test "$FALKORDB_SOCKET_PATH" = "$runtime_db_dir/falkordb.sock"
        test "${FALKORDB_PORT:-}" = "0"
        test "${#FALKORDB_SOCKET_PATH}" -lt 100
        printf 'MCP_STARTED runtime_db=%s persistent_db=%s socket=%s\n' \
            "$FALKORDB_PATH" "$persistent_db_dir/falkordb.db" "$FALKORDB_SOCKET_PATH"
        ;;
    *)
        printf 'unexpected fake python arguments: %s\n' "$*" >&2
        exit 2
        ;;
esac
EOF
    chmod +x "$runtime_root/venv/bin/python"
    cat >"$runtime_root/bin/uv" <<'EOF'
#!/bin/sh
set -eu
case "${1:-}" in
    --version) printf '%s\n' 'uv 0.11.31' ;;
    python) test "${2:-}" = "install" ;;
    sync) exit 0 ;;
    *) printf 'unexpected fake uv arguments: %s\n' "$*" >&2; exit 2 ;;
esac
EOF
    chmod +x "$runtime_root/bin/uv"
    lock_hash=$(sha256_file "$FIXTURE_ROOT/tools/code-intelligence/uv.lock")
    printf '%s\n' "$lock_hash" >"$runtime_root/uv.lock.sha256"
}

test_local_codex_config_merge() {
    create_fixture
    fixture_script="$FIXTURE_ROOT/script/codex/code-intelligence.sh"
    mkdir -p "$FIXTURE_ROOT/.codex"
    printf '%s\n' \
        'approval_policy = "never"' \
        '' \
        'sandbox_mode = "danger-full-access"' \
        >"$FIXTURE_ROOT/.codex/config.toml"

    "$fixture_script" activate-codex
    "$fixture_script" activate-codex

    if grep -q '^approval_policy = "never"$' "$FIXTURE_ROOT/.codex/config.toml" \
        && grep -q '^sandbox_mode = "danger-full-access"$' "$FIXTURE_ROOT/.codex/config.toml" \
        && test "$(grep -c '^\[mcp_servers\.pastera_codegraph\]$' "$FIXTURE_ROOT/.codex/config.toml")" -eq 1 \
        && grep -q 'args = \["script/codex/code-intelligence.sh", "mcp-codegraph"\]' "$FIXTURE_ROOT/.codex/config.toml"; then
        pass "activation preserves local Codex settings and adds one MCP block"
    else
        fail "activation preserves local Codex settings and adds one MCP block"
    fi
}

test_watcher_lifecycle() {
    if ! test -x "$SCRIPT_PATH" \
        || ! test -f "$PROJECT_ROOT/tools/code-intelligence/uv.lock" \
        || ! test -f "$PROJECT_ROOT/.codegraphcontext/.env" \
        || ! test -f "$PROJECT_ROOT/.codegraphcontext/config.yaml" \
        || ! test -f "$PROJECT_ROOT/.cgcignore"; then
        fail "watcher starts once, reports status, and stops"
        return
    fi

    create_fixture
    fixture_script="$FIXTURE_ROOT/script/codex/code-intelligence.sh"

    "$fixture_script" ensure-codegraph-watcher >/dev/null
    first_pid=$(sed -n '1p' "$FIXTURE_ROOT/.codegraphcontext/runtime/watcher.pid")
    "$fixture_script" ensure-codegraph-watcher >/dev/null
    second_pid=$(sed -n '1p' "$FIXTURE_ROOT/.codegraphcontext/runtime/watcher.pid")
    status_output=$("$fixture_script" status)

    if test "$first_pid" = "$second_pid" \
        && kill -0 "$first_pid" 2>/dev/null \
        && assert_contains "$status_output" "watcher=running"; then
        pass "watcher starts once, reports status, and stops"
    else
        fail "watcher starts once, reports status, and stops"
        return
    fi

    "$fixture_script" stop-codegraph-watcher >/dev/null
    if ! kill -0 "$first_pid" 2>/dev/null \
        && test "$("$fixture_script" status | grep -c 'watcher=stopped')" -eq 1; then
        pass "stop terminates only the managed watcher"
    else
        fail "stop terminates only the managed watcher"
    fi
}

test_concurrent_watcher_start() {
    create_fixture
    fixture_script="$FIXTURE_ROOT/script/codex/code-intelligence.sh"
    first_output="$FIXTURE_ROOT/first-ensure.log"
    second_output="$FIXTURE_ROOT/second-ensure.log"

    "$fixture_script" ensure-codegraph-watcher >"$first_output" 2>&1 &
    first_ensure_pid=$!
    "$fixture_script" ensure-codegraph-watcher >"$second_output" 2>&1 &
    second_ensure_pid=$!

    first_status=0
    second_status=0
    wait "$first_ensure_pid" || first_status=$?
    wait "$second_ensure_pid" || second_status=$?

    watcher_pid=$(sed -n '1p' "$FIXTURE_ROOT/.codegraphcontext/runtime/watcher.pid")
    ready_count=$(grep -c 'Monitoring for file changes' "$FIXTURE_ROOT/.codegraphcontext/runtime/watcher.log" || true)
    if test "$first_status" -eq 0 \
        && test "$second_status" -eq 0 \
        && test "$ready_count" -eq 1 \
        && kill -0 "$watcher_pid" 2>/dev/null; then
        pass "concurrent startup converges on one watcher"
    else
        sed -n '1,80p' "$first_output"
        sed -n '1,80p' "$second_output"
        fail "concurrent startup converges on one watcher"
    fi

    "$fixture_script" stop-codegraph-watcher >/dev/null
}

test_watcher_lock_honors_startup_timeout() {
    create_fixture
    fixture_script="$FIXTURE_ROOT/script/codex/code-intelligence.sh"
    runtime_state="$FIXTURE_ROOT/.codegraphcontext/runtime"
    mkdir -p "$runtime_state/watcher.lock.d"
    sleep 5 &
    lock_holder=$!
    printf '%s\n' "$lock_holder" >"$runtime_state/watcher.lock.d/owner"

    if CODE_INTELLIGENCE_WATCHER_TIMEOUT=1 \
        "$fixture_script" ensure-codegraph-watcher >/dev/null 2>&1; then
        fail "watcher lock wait honors the startup timeout"
    else
        pass "watcher lock wait honors the startup timeout"
    fi

    kill "$lock_holder" 2>/dev/null || true
    wait "$lock_holder" 2>/dev/null || true
    rm -f "$runtime_state/watcher.lock.d/owner"
    rmdir "$runtime_state/watcher.lock.d" 2>/dev/null || true
}

test_in_progress_watcher_is_reused() {
    create_fixture
    fixture_script="$FIXTURE_ROOT/script/codex/code-intelligence.sh"

    if CODE_INTELLIGENCE_WATCHER_TIMEOUT=1 FAKE_CGC_READY_DELAY=2 \
        "$fixture_script" ensure-codegraph-watcher >/dev/null 2>&1; then
        fail "timed-out initial scan remains attached for the next ensure"
        return
    fi
    initial_pid=$(sed -n '1p' "$FIXTURE_ROOT/.codegraphcontext/runtime/watcher.pid")

    if CODE_INTELLIGENCE_WATCHER_TIMEOUT=5 \
        "$fixture_script" ensure-codegraph-watcher >/dev/null 2>&1; then
        resumed_pid=$(sed -n '1p' "$FIXTURE_ROOT/.codegraphcontext/runtime/watcher.pid")
        if test "$initial_pid" = "$resumed_pid" \
            && test -f "$FIXTURE_ROOT/.codegraphcontext/runtime/watcher.ready"; then
            pass "timed-out initial scan remains attached for the next ensure"
        else
            fail "timed-out initial scan remains attached for the next ensure"
        fi
    else
        fail "timed-out initial scan remains attached for the next ensure"
    fi

    "$fixture_script" stop-codegraph-watcher >/dev/null
}

test_kuzu_fallback_is_rejected() {
    create_fixture
    fixture_script="$FIXTURE_ROOT/script/codex/code-intelligence.sh"

    if FAKE_CGC_CREATE_KUZU=true \
        "$fixture_script" ensure-codegraph-watcher >/dev/null 2>&1; then
        fail "unexpected Kuzu fallback is rejected"
    else
        pass "unexpected Kuzu fallback is rejected"
    fi

    "$fixture_script" stop-codegraph-watcher >/dev/null 2>&1 || true
}

test_identity_mismatch_is_safe() {
    if test -z "$FIXTURE_ROOT" || ! test -d "$FIXTURE_ROOT"; then
        fail "stop refuses an unrelated PID"
        return
    fi

    sleep 30 &
    INNOCENT_PID=$!
    runtime_state="$FIXTURE_ROOT/.codegraphcontext/runtime"
    mkdir -p "$runtime_state"
    printf '%s\n' "$INNOCENT_PID" >"$runtime_state/watcher.pid"

    if "$FIXTURE_ROOT/script/codex/code-intelligence.sh" stop-codegraph-watcher >/dev/null 2>&1; then
        fail "stop refuses an unrelated PID"
    elif kill -0 "$INNOCENT_PID" 2>/dev/null; then
        pass "stop refuses an unrelated PID"
    else
        fail "stop refuses an unrelated PID"
    fi
    kill "$INNOCENT_PID" 2>/dev/null || true
    wait "$INNOCENT_PID" 2>/dev/null || true
    INNOCENT_PID=
    rm -f "$runtime_state/watcher.pid"
}

test_reindex_generation_and_mcp() {
    if test -z "$FIXTURE_ROOT" || ! test -d "$FIXTURE_ROOT"; then
        fail "reindex advances the derived database generation"
        fail "MCP wrapper exports worktree-local database paths"
        return
    fi

    fixture_script="$FIXTURE_ROOT/script/codex/code-intelligence.sh"
    "$fixture_script" reindex-codegraph >/dev/null
    generation=$(sed -n '1p' "$FIXTURE_ROOT/.codegraphcontext/runtime/generation")
    if test "$generation" = "1"; then
        pass "reindex advances the derived database generation"
    else
        fail "reindex advances the derived database generation"
    fi

    if ! mcp_output=$("$fixture_script" mcp-codegraph 2>&1); then
        printf '%s\n' "$mcp_output"
        fail "MCP wrapper exports a worktree-local FalkorDB file and socket"
        return
    fi
    if assert_contains "$mcp_output" "MCP_STARTED" \
        && assert_contains "$mcp_output" "runtime_db=/tmp/cgc-" \
        && assert_contains "$mcp_output" "persistent_db=$FIXTURE_ROOT/.codegraphcontext/db/" \
        && assert_contains "$mcp_output" "socket=/tmp/cgc-" \
        && assert_contains "$mcp_output" "/falkordb.sock"; then
        pass "MCP wrapper exports a persistent database through a short runtime path"
    else
        printf '%s\n' "$mcp_output"
        fail "MCP wrapper exports a persistent database through a short runtime path"
    fi
}

test_stale_runtime_sync_accepts_version_on_stderr() {
    create_fixture
    fixture_script="$FIXTURE_ROOT/script/codex/code-intelligence.sh"
    printf '%s\n' 'stale-lock-hash' \
        >"$FIXTURE_ROOT/.git/codex-code-intelligence/uv.lock.sha256"

    if mcp_output=$("$fixture_script" mcp-codegraph 2>&1) \
        && assert_contains "$mcp_output" "MCP_STARTED"; then
        pass "runtime sync accepts CodeGraphContext version output on stderr"
    else
        printf '%s\n' "${mcp_output:-}"
        fail "runtime sync accepts CodeGraphContext version output on stderr"
    fi
}

test_project_contract
if ! test -x "$SCRIPT_PATH"; then
    printf '# %s of %s checks failed\n' "$FAILURES" "$TESTS"
    exit 1
fi
test_local_codex_config_merge
test_output_budget_does_not_rotate_database
test_missing_runtime_status
test_watcher_lifecycle
test_concurrent_watcher_start
test_watcher_lock_honors_startup_timeout
test_in_progress_watcher_is_reused
test_kuzu_fallback_is_rejected
test_identity_mismatch_is_safe
test_reindex_generation_and_mcp
test_stale_runtime_sync_accepts_version_on_stderr

if test "$FAILURES" -ne 0; then
    printf '# %s of %s checks failed\n' "$FAILURES" "$TESTS"
    exit 1
fi

printf '# all %s checks passed\n' "$TESTS"
