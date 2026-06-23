#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASK_PATH="${ROOT_DIR}/Casks/pastera.rb"
VERSION=""
TAG=""
DMG_PATH=""
CHECK_URL=1

usage() {
    cat <<EOF
Usage: $0 --version VERSION --dmg PATH [--tag TAG] [--no-check-url]

Updates Casks/pastera.rb from a release DMG by refreshing:
  - version
  - sha256
  - GitHub Release DMG URL

Examples:
  $0 --version "2.0.1-beta" --dmg ".build/release-artifacts/Pastera-2.0.1-beta-macOS.dmg"
  $0 --version "2.0.1-beta" --tag "v2.0.1-beta" --dmg ".build/unsigned-beta-dmg/Pastera-2.0.1-beta-macOS.dmg" --no-check-url
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
        --dmg)
            DMG_PATH="${2:?Missing value for --dmg}"
            shift 2
            ;;
        --check-url)
            CHECK_URL=1
            shift
            ;;
        --no-check-url)
            CHECK_URL=0
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

if [[ -z "${VERSION}" || -z "${DMG_PATH}" ]]; then
    usage >&2
    exit 2
fi

if [[ -z "${TAG}" ]]; then
    TAG="v${VERSION}"
fi

if [[ ! -f "${DMG_PATH}" ]]; then
    echo "DMG not found: ${DMG_PATH}" >&2
    exit 1
fi

expected_name="Pastera-${VERSION}-macOS.dmg"
actual_name="$(basename "${DMG_PATH}")"
if [[ "${actual_name}" != "${expected_name}" ]]; then
    echo "DMG name must be ${expected_name}; got ${actual_name}" >&2
    exit 1
fi

SHA256="$(shasum -a 256 "${DMG_PATH}" | awk '{print $1}')"
URL="https://github.com/pastera-app/Pastera/releases/download/${TAG}/Pastera-${VERSION}-macOS.dmg"

if [[ "${CHECK_URL}" == "1" ]]; then
    if ! /usr/bin/curl --fail --location --head --silent --show-error "${URL}" >/dev/null; then
        echo "Release DMG URL is not reachable: ${URL}" >&2
        echo "Upload ${expected_name} first, or pass --no-check-url for local-only cask preparation." >&2
        exit 1
    fi
fi

PASTERA_CASK_VERSION="${VERSION}" PASTERA_CASK_SHA256="${SHA256}" /usr/bin/perl -0pi -e '
    my $version = $ENV{"PASTERA_CASK_VERSION"};
    my $sha256 = $ENV{"PASTERA_CASK_SHA256"};
    s/version "[^"]+"/version "$version"/;
    s/sha256 "[^"]+"/sha256 "$sha256"/;
' "${CASK_PATH}"

printf 'Updated Homebrew Cask: %s\n' "${CASK_PATH}"
printf 'version "%s"\n' "${VERSION}"
printf 'sha256 "%s"\n' "${SHA256}"
printf 'url "%s"\n' "${URL}"
