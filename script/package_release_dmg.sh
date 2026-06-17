#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Pastera"
APP_TARGET="pastera"
PROJECT_PATH="${ROOT_DIR}/pastera.xcodeproj"
BUILD_ROOT="${BUILD_ROOT:-${ROOT_DIR}/.build/release-dmg}"
PRODUCTS_DIR="${BUILD_ROOT}/Products"
OBJROOT="${BUILD_ROOT}/Intermediates.noindex"
STAGING_DIR="${BUILD_ROOT}/dmg-staging"
APP_PATH="${PRODUCTS_DIR}/Release/${APP_NAME}.app"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-}"
VERSION=""
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT_DIR}/.build/release-artifacts}"
SKIP_NOTARIZATION=0
SKIP_BUILD=0

usage() {
    cat <<EOF
Usage: $0 [--version VERSION] [--output-dir DIR] [--skip-build] [--skip-notarization]

Builds a Release Pastera.app, notarizes it, creates a DMG with an Applications
alias, notarizes the DMG, and prints the final DMG path.

Required for real releases:
  DEVELOPER_ID_APPLICATION="Developer ID Application: Name (TEAMID)"
  NOTARY_KEYCHAIN_PROFILE=<notarytool keychain profile>

Optional:
  DEVELOPMENT_TEAM=<Apple developer team id>
  BUILD_ROOT=.build/release-dmg
  OUTPUT_DIR=.build/release-artifacts
EOF
}

while (($#)); do
    case "$1" in
        --version)
            VERSION="${2:?Missing value for --version}"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="${2:?Missing value for --output-dir}"
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        --skip-notarization)
            SKIP_NOTARIZATION=1
            shift
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
done

if [[ -z "${VERSION}" ]]; then
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${ROOT_DIR}/pastera/Supporting Files/Info.plist")"
fi

if [[ "${SKIP_NOTARIZATION}" != "1" ]]; then
    if [[ -z "${DEVELOPER_ID_APPLICATION}" ]]; then
        echo "DEVELOPER_ID_APPLICATION is required unless --skip-notarization is passed." >&2
        exit 2
    fi

    if [[ -z "${NOTARY_KEYCHAIN_PROFILE}" ]]; then
        echo "NOTARY_KEYCHAIN_PROFILE is required unless --skip-notarization is passed." >&2
        exit 2
    fi
fi

DMG_NAME="${APP_NAME}-${VERSION}-macOS.dmg"
DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"
APP_ZIP_PATH="${BUILD_ROOT}/${APP_NAME}-${VERSION}-macOS-app.zip"

XCODEBUILD_ARGS=(
    -project "${PROJECT_PATH}"
    -target "${APP_TARGET}"
    -configuration Release
    -clonedSourcePackagesDirPath "${ROOT_DIR}/.spm-cache/SourcePackages"
    -packageCachePath "${ROOT_DIR}/.spm-cache/PackageCache"
    -skipPackagePluginValidation
    -skipMacroValidation
    SYMROOT="${PRODUCTS_DIR}"
    OBJROOT="${OBJROOT}"
    CODE_SIGN_STYLE=Manual
    ENABLE_HARDENED_RUNTIME=YES
)

if [[ "${SKIP_NOTARIZATION}" == "1" ]]; then
    XCODEBUILD_ARGS+=(
        CODE_SIGNING_ALLOWED=NO
        CODE_SIGNING_REQUIRED=NO
        CODE_SIGN_IDENTITY=-
        OTHER_CODE_SIGN_FLAGS=
    )
else
    XCODEBUILD_ARGS+=(
        CODE_SIGNING_ALLOWED=YES
        CODE_SIGNING_REQUIRED=YES
        CODE_SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION}"
        OTHER_CODE_SIGN_FLAGS=--timestamp
    )
fi

if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    XCODEBUILD_ARGS+=(DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}")
fi

if [[ "${SKIP_BUILD}" != "1" ]]; then
    (cd "${ROOT_DIR}" && xcodebuild "${XCODEBUILD_ARGS[@]}" clean build)
fi

if [[ ! -d "${APP_PATH}" ]]; then
    echo "Built app not found: ${APP_PATH}" >&2
    exit 1
fi

if [[ "${SKIP_NOTARIZATION}" == "1" ]]; then
    /usr/bin/codesign --force --deep --sign - "${APP_PATH}"
fi

/usr/bin/codesign --verify --deep --strict --verbose=4 "${APP_PATH}"

if [[ "${SKIP_NOTARIZATION}" != "1" ]]; then
    rm -f "${APP_ZIP_PATH}"
    /usr/bin/ditto -c -k --keepParent "${APP_PATH}" "${APP_ZIP_PATH}"
    xcrun notarytool submit "${APP_ZIP_PATH}" --keychain-profile "${NOTARY_KEYCHAIN_PROFILE}" --wait
    xcrun stapler staple "${APP_PATH}"
    xcrun stapler validate "${APP_PATH}"
    /usr/sbin/spctl -a -vv "${APP_PATH}"
fi

rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}" "${OUTPUT_DIR}"
/usr/bin/ditto "${APP_PATH}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"
rm -f "${DMG_PATH}"
hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGING_DIR}" -ov -format UDZO "${DMG_PATH}"

if [[ "${SKIP_NOTARIZATION}" != "1" ]]; then
    /usr/bin/codesign --force --sign "${DEVELOPER_ID_APPLICATION}" --timestamp "${DMG_PATH}"
    xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARY_KEYCHAIN_PROFILE}" --wait
    xcrun stapler staple "${DMG_PATH}"
    xcrun stapler validate "${DMG_PATH}"
    /usr/sbin/spctl -a -vv "${DMG_PATH}"
else
    echo "Skipped notarization; ${DMG_PATH} is not suitable for public release." >&2
fi

printf '%s\n' "${DMG_PATH}"
