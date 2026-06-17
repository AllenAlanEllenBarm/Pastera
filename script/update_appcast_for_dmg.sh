#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPCAST_PATH="${APPCAST_PATH:-${ROOT_DIR}/appcast.xml}"
SPARKLE_SIGN_UPDATE_BIN="${SPARKLE_SIGN_UPDATE_BIN:-}"
VERSION=""
TAG=""
DMG_PATH=""

usage() {
    cat <<EOF
Usage: $0 --version VERSION --tag TAG --dmg PATH

Updates appcast.xml for a signed DMG release. SPARKLE_PRIVATE_KEY must contain
the EdDSA private key used by Sparkle; it is read from the environment and never
written to disk.
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

if [[ -z "${VERSION}" || -z "${TAG}" || -z "${DMG_PATH}" ]]; then
    usage >&2
    exit 2
fi

if [[ ! -f "${DMG_PATH}" ]]; then
    echo "DMG not found: ${DMG_PATH}" >&2
    exit 1
fi

if [[ -z "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    echo "SPARKLE_PRIVATE_KEY is required to sign the DMG for Sparkle." >&2
    exit 2
fi

if [[ -z "${SPARKLE_SIGN_UPDATE_BIN}" ]]; then
    for candidate in \
        "${ROOT_DIR}/.spm-cache/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update" \
        "${ROOT_DIR}/.spm-cache/SourcePackages/checkouts/Sparkle/sign_update"; do
        if [[ -x "${candidate}" ]]; then
            SPARKLE_SIGN_UPDATE_BIN="${candidate}"
            break
        fi
    done
fi

if [[ -z "${SPARKLE_SIGN_UPDATE_BIN}" || ! -x "${SPARKLE_SIGN_UPDATE_BIN}" ]]; then
    echo "Sparkle sign_update not found. Build packages first or set SPARKLE_SIGN_UPDATE_BIN." >&2
    exit 1
fi

signature_output="$(printf '%s' "${SPARKLE_PRIVATE_KEY}" | "${SPARKLE_SIGN_UPDATE_BIN}" --ed-key-file - "${DMG_PATH}")"
length="$(printf '%s\n' "${signature_output}" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"
ed_signature="$(printf '%s\n' "${signature_output}" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"

if [[ -z "${length}" || -z "${ed_signature}" ]]; then
    echo "Could not parse Sparkle signature output:" >&2
    printf '%s\n' "${signature_output}" >&2
    exit 1
fi

release_url="https://github.com/AllenAlanEllenBarm/Pastera/releases/download/${TAG}/Pastera-${VERSION}-macOS.dmg"
release_page="https://github.com/AllenAlanEllenBarm/Pastera/releases/tag/${TAG}"

PASTERA_APPCAST_URL="${release_url}" \
PASTERA_APPCAST_RELEASE_PAGE="${release_page}" \
PASTERA_APPCAST_LENGTH="${length}" \
PASTERA_APPCAST_SIGNATURE="${ed_signature}" \
PASTERA_APPCAST_VERSION="${VERSION}" \
/usr/bin/perl -0pi -e '
    my $url = $ENV{"PASTERA_APPCAST_URL"};
    my $page = $ENV{"PASTERA_APPCAST_RELEASE_PAGE"};
    my $length = $ENV{"PASTERA_APPCAST_LENGTH"};
    my $signature = $ENV{"PASTERA_APPCAST_SIGNATURE"};
    my $version = $ENV{"PASTERA_APPCAST_VERSION"};
    s#(<item>\s*<title>)[^<]+(</title>)#$1 . "Pastera $version" . $2#se;
    s#(<item>.*?<link>)[^<]+(</link>)#$1 . $page . $2#se;
    s#(<sparkle:releaseNotesLink>)[^<]+(</sparkle:releaseNotesLink>)#$1 . $page . $2#se;
    s#(url=")[^"]+(")#$1 . $url . $2#e;
    s#(length=")[^"]+(")#$1 . $length . $2#e;
    s#(type=")[^"]+(")#$1 . "application/x-apple-diskimage" . $2#e;
    s#(sparkle:version=")[^"]+(")#$1 . $version . $2#e;
    s#(sparkle:shortVersionString=")[^"]+(")#$1 . $version . $2#e;
    if (s#sparkle:edSignature="[^"]+"#sparkle:edSignature="$signature"#) {
        # Existing signature replaced.
    } else {
        s#(sparkle:shortVersionString="[^"]+")#$1\n                sparkle:edSignature="$signature"#;
    }
' "${APPCAST_PATH}"
