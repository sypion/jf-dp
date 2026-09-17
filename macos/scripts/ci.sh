#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

for name in VERSION CSC_LINK CSC_KEY_PASSWORD APPLE_ID APPLE_APP_SPECIFIC_PASSWORD APPLE_TEAM_ID SPARKLE_PRIVATE_KEY GH_TOKEN GITHUB_REPOSITORY; do
	eval "value=\${$name:-}"
	if [ -z "$value" ]; then
		echo "$name is not set." >&2
		exit 1
	fi
done

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ]; then
	export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

case "$CSC_LINK" in
	/* | file:*)
		echo "CI needs the base64 of the .p12" >&2
		exit 1
		;;
esac

umask 077
workdir=$(mktemp -d)
keychain="$workdir/signing.keychain"
keychain_password=$(openssl rand -base64 24)
p12="$workdir/certificate.p12"

echo "::add-mask::$keychain_password"

# The draft release starts with these same generated notes. Publishing it swaps in the release's final notes.
NOTES="$workdir/notes.md"
gh api "repos/$GITHUB_REPOSITORY/releases/generate-notes" -f tag_name="${TAG:-v$VERSION}" --jq .body >"$NOTES"
export NOTES

cleanup() {
	security delete-keychain "$keychain" >/dev/null 2>&1 || true
	rm -rf "$workdir"
}
trap cleanup EXIT INT TERM

if ! printf '%s' "$CSC_LINK" | base64 -d >"$p12" 2>/dev/null; then
	echo "CSC_LINK is not valid base64" >&2
	exit 1
fi

security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$p12" -k "$keychain" -f pkcs12 -P "$CSC_KEY_PASSWORD" -T /usr/bin/codesign

rm -f "$p12"

security set-key-partition-list \
	-S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null

# shellcheck disable=SC2046
security list-keychains -d user -s "$keychain" $(security list-keychains -d user | tr -d '"')

SIGN_IDENTITY=$(security find-identity -v -p codesigning "$keychain" | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)
if [ -z "$SIGN_IDENTITY" ]; then
	echo "no \"Developer ID Application\" identity in the signing keychain; check CSC_LINK and CSC_KEY_PASSWORD" >&2
	exit 1
fi
export SIGN_IDENTITY

swift test
scripts/release.sh
