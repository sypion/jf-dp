#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

: "${VERSION:?Set VERSION, like VERSION=1.2.0}"
: "${APPLE_ID:?Set APPLE_ID}"
: "${APPLE_APP_SPECIFIC_PASSWORD:?Set APPLE_APP_SPECIFIC_PASSWORD}"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID}"
: "${SPARKLE_PRIVATE_KEY:?Set SPARKLE_PRIVATE_KEY to sign the update}"

REPOSITORY="${GITHUB_REPOSITORY:-sypion/jf-dp}"
# The release's tag: vX.Y.Z, or macos-vX.Y.Z when only the app is released.
TAG="${TAG:-v$VERSION}"
DOWNLOAD_PREFIX="${DOWNLOAD_PREFIX:-https://github.com/$REPOSITORY/releases/download/$TAG/}"

if [ -z "${SIGN_IDENTITY:-}" ]; then
	SIGN_IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
fi
: "${SIGN_IDENTITY:?No Developer ID Application identity found}"

if [ -z "${BUILD_NUMBER:-}" ]; then
	if ! BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null)"; then
		echo "error: release from a commit (or set BUILD_NUMBER); there's no git history to number the build" >&2
		exit 1
	fi
	if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
		echo "error: this is a shallow clone, so the commit count is wrong; fetch the full history (or set BUILD_NUMBER)" >&2
		exit 1
	fi
fi

export VERSION SIGN_IDENTITY BUILD_NUMBER

APP="$(scripts/bundle.sh release | tail -1)"
DMG="release/jf-dp_macos.dmg"

rm -rf release
mkdir -p release

notarize() {
	xcrun notarytool submit "$1" \
		--apple-id "$APPLE_ID" \
		--password "$APPLE_APP_SPECIFIC_PASSWORD" \
		--team-id "$APPLE_TEAM_ID" \
		--wait
}

ditto -c -k --keepParent "$APP" "release/notarize.zip"
notarize "release/notarize.zip"
xcrun stapler staple "$APP"
rm "release/notarize.zip"

ditto -c -k --sequesterRsrc --keepParent "$APP" "release/jf-dp_macos.zip"

scripts/make-dmg.sh "$APP" "$DMG"

codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"

# The appcast lists only this version: that's all Sparkle needs to offer it.
GENERATE="$(find .build/artifacts -name generate_appcast -type f | head -1)"
FEED_DIR="$(mktemp -d)"
cp "release/jf-dp_macos.zip" "$FEED_DIR/"
if [ -n "${NOTES:-}" ]; then
	cp "$NOTES" "$FEED_DIR/jf-dp_macos.md"
fi
printf '%s' "$SPARKLE_PRIVATE_KEY" | "$GENERATE" \
	--ed-key-file - \
	--download-url-prefix "$DOWNLOAD_PREFIX" \
	--embed-release-notes \
	"$FEED_DIR"
cp "$FEED_DIR/appcast.xml" release/appcast.xml
rm -rf "$FEED_DIR"

spctl -a -t exec -vv "$APP"
echo "Built $DMG, release/jf-dp_macos.zip and release/appcast.xml"
