#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=""
TAG=""
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT_DIR}/.build/release-artifacts}"
SKIP_NOTARIZATION=0
SKIP_BUILD=0
UPDATE_APPCAST=0

usage() {
    cat <<EOF
Usage: $0 [--version VERSION] [--tag TAG] [--output-dir DIR] [--skip-build] [--skip-notarization] [--update-appcast]

Builds the release DMG through script/package_release_dmg.sh. When
--update-appcast is passed, this also updates appcast.xml through
script/update_appcast_for_dmg.sh.

Real public release:
  DEVELOPER_ID_APPLICATION="Developer ID Application: Name (TEAMID)" \\
  DEVELOPMENT_TEAM="TEAMID" \\
  NOTARY_KEYCHAIN_PROFILE="PasteraNotary" \\
  SPARKLE_PRIVATE_KEY="<from secrets>" \\
  $0 --version "2.0.1-beta" --tag "v2.0.1-beta" --update-appcast

Local dry run without notarization:
  $0 --version "2.0.1-beta" --skip-notarization
EOF
}

while (($#)); do
    case "$1" in
        --version)
            VERSION="${2:?Missing value for --version}"
            shift 2
            ;;
        --tag)
            TAG="${2:?Missing value for --tag}"
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
        --update-appcast)
            UPDATE_APPCAST=1
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

if [[ "${UPDATE_APPCAST}" == "1" && -z "${TAG}" ]]; then
    echo "--tag is required when --update-appcast is passed." >&2
    exit 2
fi

if [[ "${UPDATE_APPCAST}" == "1" && "${SKIP_NOTARIZATION}" == "1" ]]; then
    echo "--update-appcast requires a signed and notarized DMG; do not combine it with --skip-notarization." >&2
    exit 2
fi

package_args=(
    --version "${VERSION}"
    --output-dir "${OUTPUT_DIR}"
)

if [[ "${SKIP_BUILD}" == "1" ]]; then
    package_args+=(--skip-build)
fi

if [[ "${SKIP_NOTARIZATION}" == "1" ]]; then
    package_args+=(--skip-notarization)
fi

package_log="$(mktemp)"
trap 'rm -f "${package_log}"' EXIT

"${ROOT_DIR}/script/package_release_dmg.sh" "${package_args[@]}" | tee "${package_log}"
dmg_path="$(tail -n 1 "${package_log}")"

if [[ ! -f "${dmg_path}" ]]; then
    echo "Packaging did not produce a DMG at the reported path: ${dmg_path}" >&2
    exit 1
fi

if [[ "${UPDATE_APPCAST}" == "1" ]]; then
    "${ROOT_DIR}/script/update_appcast_for_dmg.sh" \
        --version "${VERSION}" \
        --tag "${TAG}" \
        --dmg "${dmg_path}"
    printf 'Updated appcast: %s\n' "${ROOT_DIR}/appcast.xml"
fi

printf 'Release DMG: %s\n' "${dmg_path}"
