#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPCAST_PATH="${APPCAST_PATH:-${ROOT_DIR}/appcast.xml}"
SPARKLE_GENERATE_APPCAST_BIN="${SPARKLE_GENERATE_APPCAST_BIN:-}"
TAG=""
DMG_PATH=""

usage() {
    cat <<EOF
Usage: $0 --tag TAG --dmg PATH

Generates appcast.xml from a signed and notarized DMG. Bundle versions and the
Sparkle public key are read from Pastera.app inside the DMG. SPARKLE_PRIVATE_KEY
is supplied to Sparkle through standard input and is never written to disk.
EOF
}

while (($#)); do
    case "$1" in
        --tag)
            TAG="${2:?Missing value for --tag}"
            shift 2
            ;;
        --dmg)
            DMG_PATH="${2:?Missing value for --dmg}"
            shift 2
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

if [[ -z "${TAG}" || -z "${DMG_PATH}" ]]; then
    usage >&2
    exit 2
fi
if [[ ! -f "${DMG_PATH}" ]]; then
    echo "DMG not found: ${DMG_PATH}" >&2
    exit 1
fi
if [[ -z "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    echo "SPARKLE_PRIVATE_KEY is required to generate a signed Sparkle appcast." >&2
    exit 2
fi

if [[ -z "${SPARKLE_GENERATE_APPCAST_BIN}" ]]; then
    for candidate in \
        "${ROOT_DIR}/.spm-cache/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" \
        "${ROOT_DIR}/.spm-cache/SourcePackages/checkouts/Sparkle/bin/generate_appcast"; do
        if [[ -x "${candidate}" ]]; then
            SPARKLE_GENERATE_APPCAST_BIN="${candidate}"
            break
        fi
    done
fi
if [[ -z "${SPARKLE_GENERATE_APPCAST_BIN}" || ! -x "${SPARKLE_GENERATE_APPCAST_BIN}" ]]; then
    echo "Sparkle generate_appcast not found. Build packages first or set SPARKLE_GENERATE_APPCAST_BIN." >&2
    exit 1
fi

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pastera-appcast.XXXXXX")"
MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pastera-dmg.XXXXXX")"
cleanup() {
    if [[ -n "${MOUNT_DIR:-}" && -d "${MOUNT_DIR}" ]]; then
        /usr/bin/hdiutil detach "${MOUNT_DIR}" >/dev/null 2>&1 \
            || /usr/bin/hdiutil detach -force "${MOUNT_DIR}" >/dev/null 2>&1 \
            || true
        rmdir "${MOUNT_DIR}" 2>/dev/null || true
    fi
    rm -rf "${STAGING_DIR}"
}
trap cleanup EXIT

/usr/bin/hdiutil attach -readonly -nobrowse -noverify -mountpoint "${MOUNT_DIR}" "${DMG_PATH}" >/dev/null
APP_INFO_PLIST="${MOUNT_DIR}/Pastera.app/Contents/Info.plist"
if [[ ! -f "${APP_INFO_PLIST}" ]]; then
    echo "Pastera.app metadata was not found in the DMG." >&2
    exit 1
fi

BUNDLE_SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_INFO_PLIST}")"
BUNDLE_BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${APP_INFO_PLIST}")"
SPARKLE_PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "${APP_INFO_PLIST}")"

if [[ ! "${BUNDLE_SHORT_VERSION}" =~ ^[0-9]+([.][0-9]+)*$ ]]; then
    echo "DMG contains a non-numeric CFBundleShortVersionString: ${BUNDLE_SHORT_VERSION}" >&2
    exit 1
fi
if [[ ! "${BUNDLE_BUILD_VERSION}" =~ ^[0-9]+$ ]]; then
    echo "DMG contains a non-numeric CFBundleVersion: ${BUNDLE_BUILD_VERSION}" >&2
    exit 1
fi
if [[ -z "${SPARKLE_PUBLIC_KEY}" ]]; then
    echo "DMG does not contain SUPublicEDKey." >&2
    exit 1
fi

/usr/bin/hdiutil detach "${MOUNT_DIR}" >/dev/null
rmdir "${MOUNT_DIR}"
MOUNT_DIR=""

if [[ -f "${APPCAST_PATH}" ]]; then
    /usr/bin/ditto "${APPCAST_PATH}" "${STAGING_DIR}/appcast.xml"
fi
STAGED_DMG="${STAGING_DIR}/$(basename "${DMG_PATH}")"
/usr/bin/ditto "${DMG_PATH}" "${STAGED_DMG}"

DOWNLOAD_URL_PREFIX="https://github.com/pastera-app/Pastera/releases/download/${TAG}/"
RELEASE_PAGE="https://github.com/pastera-app/Pastera/releases/tag/${TAG}"
printf '%s' "${SPARKLE_PRIVATE_KEY}" | "${SPARKLE_GENERATE_APPCAST_BIN}" \
    --ed-key-file - \
    --download-url-prefix "${DOWNLOAD_URL_PREFIX}" \
    --link "${RELEASE_PAGE}" \
    --versions "${BUNDLE_BUILD_VERSION}" \
    --maximum-versions 3 \
    "${STAGING_DIR}"

GENERATED_APPCAST="${STAGING_DIR}/appcast.xml"
if [[ ! -f "${GENERATED_APPCAST}" ]]; then
    echo "Sparkle did not generate appcast.xml." >&2
    exit 1
fi

ENCLOSURE_XPATH="(/rss/channel/item/enclosure[@sparkle:version='${BUNDLE_BUILD_VERSION}'])[1]"
xml_value() {
    /usr/bin/xmllint --xpath "string(${ENCLOSURE_XPATH}/@$1)" "${GENERATED_APPCAST}"
}

GENERATED_URL="$(xml_value url)"
GENERATED_LENGTH="$(xml_value length)"
GENERATED_TYPE="$(xml_value type)"
GENERATED_BUILD_VERSION="$(xml_value sparkle:version)"
GENERATED_SHORT_VERSION="$(xml_value sparkle:shortVersionString)"
GENERATED_SIGNATURE="$(xml_value sparkle:edSignature)"
EXPECTED_URL="${DOWNLOAD_URL_PREFIX}$(basename "${DMG_PATH}")"
EXPECTED_LENGTH="$(/usr/bin/stat -f '%z' "${DMG_PATH}")"

if [[ "${GENERATED_URL}" != "${EXPECTED_URL}" ]]; then
    echo "Generated appcast URL does not match the release asset." >&2
    exit 1
fi
if [[ "${GENERATED_LENGTH}" != "${EXPECTED_LENGTH}" ]]; then
    echo "Generated appcast length does not match the DMG." >&2
    exit 1
fi
if [[ "${GENERATED_TYPE}" != "application/x-apple-diskimage" ]]; then
    echo "Generated appcast uses an unexpected enclosure type: ${GENERATED_TYPE}" >&2
    exit 1
fi
if [[ "${GENERATED_BUILD_VERSION}" != "${BUNDLE_BUILD_VERSION}" \
      || "${GENERATED_SHORT_VERSION}" != "${BUNDLE_SHORT_VERSION}" \
      || -z "${GENERATED_SIGNATURE}" ]]; then
    echo "Generated appcast metadata does not match the application bundle." >&2
    exit 1
fi

/usr/bin/swift "${ROOT_DIR}/script/verify_sparkle_ed_signature.swift" \
    "${SPARKLE_PUBLIC_KEY}" \
    "${GENERATED_SIGNATURE}" \
    "${DMG_PATH}"

APPCAST_DIR="$(dirname "${APPCAST_PATH}")"
mkdir -p "${APPCAST_DIR}"
APPCAST_TEMP="$(mktemp "${APPCAST_DIR}/.$(basename "${APPCAST_PATH}").XXXXXX")"
/usr/bin/ditto "${GENERATED_APPCAST}" "${APPCAST_TEMP}"
mv "${APPCAST_TEMP}" "${APPCAST_PATH}"

printf 'Updated appcast for Pastera %s (build %s).\n' \
    "${BUNDLE_SHORT_VERSION}" \
    "${BUNDLE_BUILD_VERSION}"
