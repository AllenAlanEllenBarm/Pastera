#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-Pastera}"
APP_PATH="${APP_PATH:-/Applications/Pastera.app}"
LAUNCH_ARGUMENT="${LAUNCH_ARGUMENT:---pastera-open-setup-guide}"

console_user() {
    /usr/bin/stat -f%Su /dev/console 2>/dev/null || true
}

console_user_id() {
    local user
    user="$(console_user)"
    if [[ -z "${user}" || "${user}" == "root" || "${user}" == "_mbsetupuser" ]]; then
        return 1
    fi
    /usr/bin/id -u "${user}" 2>/dev/null
}

running_pastera_pids() {
    /usr/bin/pgrep -x "${APP_NAME}" 2>/dev/null || true
}

has_running_pastera() {
    [[ -n "$(running_pastera_pids)" ]]
}

wait_for_pastera_exit() {
    local attempts="${1:-30}"
    local interval="${2:-0.2}"

    for _ in $(/usr/bin/seq 1 "${attempts}"); do
        if ! has_running_pastera; then
            return 0
        fi
        sleep "${interval}"
    done

    return 1
}

run_in_console_session() {
    local uid
    local user

    uid="$(console_user_id)" || return 1
    user="$(console_user)"
    /bin/launchctl asuser "${uid}" /usr/bin/sudo -u "${user}" "$@"
}

request_pastera_quit() {
    if [[ "${EUID:-$(/usr/bin/id -u)}" == "0" ]]; then
        run_in_console_session /usr/bin/osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
    else
        /usr/bin/osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
    fi
}

quit_running_pastera() {
    if ! has_running_pastera; then
        return 0
    fi

    request_pastera_quit
    if wait_for_pastera_exit 30 0.2; then
        return 0
    fi

    /usr/bin/pkill -TERM -x "${APP_NAME}" >/dev/null 2>&1 || true
    if wait_for_pastera_exit 20 0.2; then
        return 0
    fi

    /usr/bin/pkill -KILL -x "${APP_NAME}" >/dev/null 2>&1 || true
    if wait_for_pastera_exit 10 0.2; then
        return 0
    fi

    echo "Failed to quit running ${APP_NAME} before replacing ${APP_PATH}." >&2
    running_pastera_pids >&2
    return 1
}

open_setup_guide_for_console_user() {
    local uid
    local user

    [[ -d "${APP_PATH}" ]] || return 0
    uid="$(console_user_id)" || return 0
    user="$(console_user)"

    /bin/launchctl asuser "${uid}" \
        /usr/bin/sudo -u "${user}" \
        /usr/bin/open "${APP_PATH}" --args "${LAUNCH_ARGUMENT}" >/dev/null 2>&1 || true
}
