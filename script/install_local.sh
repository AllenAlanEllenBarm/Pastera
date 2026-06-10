#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Pastera"
APP_BUNDLE="${APP_NAME}.app"
SCHEME="pastera"
APP_TARGET="pastera"
PROJECT_PATH="${ROOT_DIR}/pastera.xcodeproj"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${ROOT_DIR}/.build/xcode-derived-data}"
INSTALL_DIR="${PASTERA_INSTALL_DIR:-/Applications}"
DEST_APP="${INSTALL_DIR}/${APP_BUNDLE}"
TARGET_BUILD_ROOT="${DERIVED_DATA_PATH}/AppTargetBuild"
TARGET_PRODUCTS_DIR="${TARGET_BUILD_ROOT}/Products"
TARGET_OBJROOT="${TARGET_BUILD_ROOT}/Intermediates.noindex"
BUILT_APP="${TARGET_PRODUCTS_DIR}/${CONFIGURATION}/${APP_BUNDLE}"

SHOULD_BUILD=1
SHOULD_LAUNCH=1
SHOULD_CLEAN=0
SHOULD_TEST=0

usage() {
    cat <<EOF
Usage: $0 [--clean] [--test] [--no-build] [--no-launch]

Builds ${APP_BUNDLE}, installs it to:
  ${DEST_APP}

Environment overrides:
  CONFIGURATION=Debug|Release
  DERIVED_DATA_PATH=/path/to/DerivedData
  PASTERA_INSTALL_DIR=/Applications
EOF
}

while (($#)); do
    case "$1" in
        --clean)
            SHOULD_CLEAN=1
            ;;
        --test)
            SHOULD_TEST=1
            ;;
        --no-build)
            SHOULD_BUILD=0
            ;;
        --no-launch)
            SHOULD_LAUNCH=0
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

XCODEBUILD_ARGS=(
    CODE_SIGN_IDENTITY=-
    CODE_SIGNING_REQUIRED=NO
    CODE_SIGNING_ALLOWED=NO
    -project "${PROJECT_PATH}"
    -configuration "${CONFIGURATION}"
    -clonedSourcePackagesDirPath "${ROOT_DIR}/.spm-cache/SourcePackages"
    -packageCachePath "${ROOT_DIR}/.spm-cache/PackageCache"
    -skipPackagePluginValidation
    -skipMacroValidation
)

run_app_target_build() {
    (cd "${ROOT_DIR}" && xcodebuild "${XCODEBUILD_ARGS[@]}" \
        -target "${APP_TARGET}" \
        SYMROOT="${TARGET_PRODUCTS_DIR}" \
        OBJROOT="${TARGET_OBJROOT}" \
        "$@")
}

run_scheme_tests() {
    (cd "${ROOT_DIR}" && xcodebuild "${XCODEBUILD_ARGS[@]}" \
        -scheme "${SCHEME}" \
        -derivedDataPath "${DERIVED_DATA_PATH}" \
        "$@")
}

quit_running_app() {
    if ! pgrep -x "${APP_NAME}" >/dev/null; then
        return
    fi

    /usr/bin/osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
    for _ in {1..20}; do
        if ! pgrep -x "${APP_NAME}" >/dev/null; then
            return
        fi
        sleep 0.2
    done

    pkill -x "${APP_NAME}" >/dev/null 2>&1 || true
}

install_app() {
    if [[ ! -d "${BUILT_APP}" ]]; then
        echo "Built app not found: ${BUILT_APP}" >&2
        exit 1
    fi

    mkdir -p "${INSTALL_DIR}"
    if [[ ! -w "${INSTALL_DIR}" ]]; then
        echo "Install directory is not writable: ${INSTALL_DIR}" >&2
        echo "Set PASTERA_INSTALL_DIR=\"${HOME}/Applications\" to install without /Applications permissions." >&2
        exit 1
    fi

    quit_running_app
    rm -rf "${DEST_APP}"
    /usr/bin/ditto "${BUILT_APP}" "${DEST_APP}"
    /usr/bin/codesign --force --deep --sign - "${DEST_APP}"
}

if [[ "${SHOULD_CLEAN}" == "1" ]]; then
    run_app_target_build clean
fi

if [[ "${SHOULD_BUILD}" == "1" ]]; then
    run_app_target_build build
fi

if [[ "${SHOULD_TEST}" == "1" ]]; then
    run_scheme_tests test
fi

install_app

if [[ "${SHOULD_LAUNCH}" == "1" ]]; then
    /usr/bin/open "${DEST_APP}"
fi

echo "Installed ${APP_BUNDLE} to ${DEST_APP}"
