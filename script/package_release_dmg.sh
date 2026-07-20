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

prepare_install_guide_assets() {
    local background_dir="${STAGING_DIR}/.background"
    local background_path="${background_dir}/pastera-dmg-guide.png"
    local icon_path="${ROOT_DIR}/Resources/pastera_logo.png"

    mkdir -p "${background_dir}"
    /usr/bin/swift "${ROOT_DIR}/script/render_dmg_install_guide.swift" "${background_path}" "${icon_path}"
    /usr/bin/chflags hidden "${background_dir}" 2>/dev/null || true

    cat > "${STAGING_DIR}/Pastera 安装说明.txt" <<'EOF'
Pastera 安装说明 / Install Guide

1. Drag Pastera.app to Applications.

2. If macOS shows "Apple cannot verify Pastera.app" or offers only Done and
   Move to Trash, Pastera has not been accepted by Gatekeeper on this Mac yet.
   Use one of Apple's standard allow paths:

   - Double-click Open Privacy & Security.webloc in this DMG, then click
     Open Anyway for Pastera.
   - Open System Settings > Privacy & Security, then click Open Anyway for
     Pastera.
   - Or Control-click /Applications/Pastera.app, choose Open, then confirm Open.

3. After Pastera opens, macOS may ask for Accessibility permission. Open System
   Settings > Privacy & Security > Accessibility, enable Pastera, then restart
   Pastera if the hotkey still asks for permission.

If this DMG is signed with Developer ID and notarized, the "cannot verify"
warning should not appear. If it still appears, check that you downloaded the
latest DMG from the official GitHub release page.
EOF

    cat > "${STAGING_DIR}/Open Privacy & Security.webloc" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>URL</key>
  <string>x-apple.systempreferences:com.apple.preference.security?General</string>
</dict>
</plist>
EOF
}

configure_dmg_window() {
    local volume_path="$1"

    /usr/bin/osascript <<EOF
tell application "Finder"
    set volumeRoot to POSIX file "${volume_path}" as alias
    open volumeRoot
    set current view of container window of volumeRoot to icon view
    set toolbar visible of container window of volumeRoot to false
    set statusbar visible of container window of volumeRoot to false
    set bounds of container window of volumeRoot to {120, 120, 980, 660}
    set icon size of icon view options of container window of volumeRoot to 96
    set arrangement of icon view options of container window of volumeRoot to not arranged
    set background picture of icon view options of container window of volumeRoot to file ".background:pastera-dmg-guide.png" of volumeRoot
    set position of item "Pastera.app" of volumeRoot to {210, 285}
    set position of item "Applications" of volumeRoot to {650, 285}
    set position of item "Open Privacy & Security.webloc" of volumeRoot to {430, 430}
    update volumeRoot without registering applications
    close container window of volumeRoot
end tell
EOF
}

sign_ad_hoc_app() {
    local helpers_dir="${APP_PATH}/Contents/Helpers"

    /usr/bin/codesign --force --deep --sign - "${APP_PATH}"
    /usr/bin/codesign --force --sign - \
        --identifier com.pastera-app.PasteraCodexMCP \
        "${helpers_dir}/PasteraCodexMCP"
    /usr/bin/codesign --force --sign - \
        --identifier com.pastera-app.PasteraClaudeMCP \
        "${helpers_dir}/PasteraClaudeMCP"
    /usr/bin/codesign --force --sign - \
        --identifier com.pastera-app.pastera \
        "${helpers_dir}/pastera"
    /usr/bin/codesign --force --sign - "${APP_PATH}"
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
RW_DMG_PATH="${BUILD_ROOT}/${APP_NAME}-${VERSION}-macOS-rw.dmg"

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
        OTHER_CODE_SIGN_FLAGS="--timestamp --identifier \$(PRODUCT_BUNDLE_IDENTIFIER)"
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
    sign_ad_hoc_app
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
prepare_install_guide_assets
rm -f "${DMG_PATH}"
rm -f "${RW_DMG_PATH}"
hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGING_DIR}" -ov -format UDRW "${RW_DMG_PATH}"

MOUNT_DIR="$(mktemp -d "${BUILD_ROOT}/dmg-mount.XXXXXX")"
cleanup_mount() {
    if [[ -n "${MOUNT_DIR:-}" && -d "${MOUNT_DIR}" ]]; then
        /usr/bin/hdiutil detach "${MOUNT_DIR}" >/dev/null 2>&1 || /usr/bin/hdiutil detach -force "${MOUNT_DIR}" >/dev/null 2>&1 || true
        rmdir "${MOUNT_DIR}" 2>/dev/null || true
    fi
}
trap cleanup_mount EXIT

hdiutil attach -readwrite -noverify -noautoopen -mountpoint "${MOUNT_DIR}" "${RW_DMG_PATH}"
configure_dmg_window "${MOUNT_DIR}"
/bin/sync
hdiutil detach "${MOUNT_DIR}"
rmdir "${MOUNT_DIR}" 2>/dev/null || true
MOUNT_DIR=""
hdiutil convert "${RW_DMG_PATH}" -format UDZO -imagekey zlib-level=9 -o "${DMG_PATH}"
rm -f "${RW_DMG_PATH}"
trap - EXIT

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
