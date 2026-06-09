#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="${ROOT_DIR}/.git/codex-pastera-last-install.sha"
INSTALL_SCRIPT="${ROOT_DIR}/script/install_local.sh"
TRACKED_PATHS=(
    "Configurations"
    "pastera"
    "pastera.xcodeproj"
)

if [[ ! -x "${INSTALL_SCRIPT}" ]]; then
    echo "Pastera install hook skipped: ${INSTALL_SCRIPT} is not executable." >&2
    exit 1
fi

fingerprint_workspace() {
    (
        cd "${ROOT_DIR}"
        git rev-parse HEAD 2>/dev/null || true
        git status --short --untracked-files=all -- "${TRACKED_PATHS[@]}"
        git diff --no-ext-diff --binary -- "${TRACKED_PATHS[@]}"
        git diff --cached --no-ext-diff --binary -- "${TRACKED_PATHS[@]}"
        git ls-files --others --exclude-standard -z -- "${TRACKED_PATHS[@]}" |
            sort -z |
            while IFS= read -r -d '' file; do
                if [[ -f "${file}" ]]; then
                    shasum -a 256 "${file}"
                fi
            done
    ) | shasum -a 256 | awk '{print $1}'
}

current_fingerprint="$(fingerprint_workspace)"
last_fingerprint=""
if [[ -f "${STATE_FILE}" ]]; then
    last_fingerprint="$(cat "${STATE_FILE}")"
fi

if [[ "${current_fingerprint}" == "${last_fingerprint}" ]]; then
    echo "Pastera install hook skipped: no workspace changes since last install."
    exit 0
fi

"${INSTALL_SCRIPT}"
printf '%s\n' "${current_fingerprint}" > "${STATE_FILE}"
