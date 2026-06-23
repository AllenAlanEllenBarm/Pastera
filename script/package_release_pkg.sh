#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Pastera"
APP_TARGET="pastera"
PROJECT_PATH="${ROOT_DIR}/pastera.xcodeproj"
BUILD_ROOT="${BUILD_ROOT:-${ROOT_DIR}/.build/release-pkg}"
PRODUCTS_DIR="${BUILD_ROOT}/Products"
OBJROOT="${BUILD_ROOT}/Intermediates.noindex"
PACKAGE_ROOT="${BUILD_ROOT}/pkg-root"
SCRIPTS_DIR="${BUILD_ROOT}/pkg-scripts"
RESOURCES_DIR="${ROOT_DIR}/script/installer-resources/pkg"
APP_PATH="${PRODUCTS_DIR}/Release/${APP_NAME}.app"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-}"
DEVELOPER_ID_INSTALLER="${DEVELOPER_ID_INSTALLER:-}"
VERSION=""
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT_DIR}/.build/release-artifacts}"
SKIP_NOTARIZATION=0
SKIP_BUILD=0

usage() {
    cat <<EOF
Usage: $0 [--version VERSION] [--output-dir DIR] [--skip-build] [--skip-notarization]

Builds a Release Pastera.app, creates a macOS Installer PKG, signs it with
Developer ID Installer, notarizes it, and prints the final PKG path.

Required for real releases:
  DEVELOPER_ID_APPLICATION="Developer ID Application: Name (TEAMID)"
  DEVELOPER_ID_INSTALLER="Developer ID Installer: Name (TEAMID)"
  NOTARY_KEYCHAIN_PROFILE=<notarytool keychain profile>

Optional:
  DEVELOPMENT_TEAM=<Apple developer team id>
  BUILD_ROOT=.build/release-pkg
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

    if [[ -z "${DEVELOPER_ID_INSTALLER}" ]]; then
        echo "DEVELOPER_ID_INSTALLER is required unless --skip-notarization is passed." >&2
        exit 2
    fi

    if [[ -z "${NOTARY_KEYCHAIN_PROFILE}" ]]; then
        echo "NOTARY_KEYCHAIN_PROFILE is required unless --skip-notarization is passed." >&2
        exit 2
    fi
fi

PKG_NAME="Pastera-${VERSION}-macOS.pkg"
PKG_PATH="${OUTPUT_DIR}/${PKG_NAME}"
COMPONENT_PKG_PATH="${BUILD_ROOT}/PasteraComponent.pkg"
UNSIGNED_PKG_PATH="${BUILD_ROOT}/Pastera-${VERSION}-macOS-unsigned.pkg"
DISTRIBUTION_PATH="${BUILD_ROOT}/Distribution.xml"

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

rm -rf "${PACKAGE_ROOT}" "${SCRIPTS_DIR}"
mkdir -p "${PACKAGE_ROOT}" "${SCRIPTS_DIR}" "${OUTPUT_DIR}"
/usr/bin/ditto "${APP_PATH}" "${PACKAGE_ROOT}/${APP_NAME}.app"
/usr/bin/install -m 0755 "${ROOT_DIR}/script/pastera_process.sh" "${SCRIPTS_DIR}/pastera_process.sh"
/usr/bin/install -m 0755 "${RESOURCES_DIR}/scripts/preinstall" "${SCRIPTS_DIR}/preinstall"
/usr/bin/install -m 0755 "${RESOURCES_DIR}/scripts/postinstall" "${SCRIPTS_DIR}/postinstall"
if ! /usr/bin/grep -q -- "quit_running_pastera" "${SCRIPTS_DIR}/preinstall"; then
    echo "preinstall must quit running Pastera before replacing /Applications/Pastera.app." >&2
    exit 1
fi
if ! /usr/bin/grep -q -- "--pastera-open-setup-guide" "${SCRIPTS_DIR}/pastera_process.sh"; then
    echo "postinstall must launch Pastera with --pastera-open-setup-guide." >&2
    exit 1
fi

cat > "${DISTRIBUTION_PATH}" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
    <title>Pastera</title>
    <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
    <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
    <welcome file="welcome.html"/>
    <readme file="readme.html"/>
    <conclusion file="conclusion.html"/>
    <choices-outline>
        <line choice="default"/>
    </choices-outline>
    <choice id="default" title="Pastera">
        <pkg-ref id="com.pastera-app.Pastera.pkg"/>
    </choice>
    <pkg-ref id="com.pastera-app.Pastera.pkg" version="${VERSION}" onConclusion="none">PasteraComponent.pkg</pkg-ref>
</installer-gui-script>
EOF

rm -f "${COMPONENT_PKG_PATH}" "${UNSIGNED_PKG_PATH}" "${PKG_PATH}"
pkgbuild \
    --root "${PACKAGE_ROOT}" \
    --install-location /Applications \
    --identifier "com.pastera-app.Pastera.pkg" \
    --version "${VERSION}" \
    --scripts "${SCRIPTS_DIR}" \
    "${COMPONENT_PKG_PATH}"

productbuild \
    --distribution "${DISTRIBUTION_PATH}" \
    --package-path "${BUILD_ROOT}" \
    --resources "${RESOURCES_DIR}" \
    "${UNSIGNED_PKG_PATH}"

if [[ "${SKIP_NOTARIZATION}" != "1" ]]; then
    productsign --sign "${DEVELOPER_ID_INSTALLER}" --timestamp "${UNSIGNED_PKG_PATH}" "${PKG_PATH}"
    rm -f "${UNSIGNED_PKG_PATH}"
    pkgutil --check-signature "${PKG_PATH}"
    xcrun notarytool submit "${PKG_PATH}" --keychain-profile "${NOTARY_KEYCHAIN_PROFILE}" --wait
    xcrun stapler staple "${PKG_PATH}"
    xcrun stapler validate "${PKG_PATH}"
    /usr/sbin/spctl -a -vv -t install "${PKG_PATH}"
else
    mv "${UNSIGNED_PKG_PATH}" "${PKG_PATH}"
    echo "Skipped notarization; ${PKG_PATH} is not suitable for public release." >&2
fi

printf '%s\n' "${PKG_PATH}"
