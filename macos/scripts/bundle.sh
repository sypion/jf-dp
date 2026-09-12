#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ]; then
	export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

MODE="${1:-debug}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
RPATH="-Xlinker -rpath -Xlinker @executable_path/../Frameworks"

if [ "$MODE" = "release" ]; then
	BUNDLE_ID="io.github.sypion.jf-dp"
	FEED_URL="${FEED_URL:-https://github.com/${GITHUB_REPOSITORY:-sypion/jf-dp}/releases/latest/download/appcast.xml}"
	# From `generate_keys --account jf-dp -p`; the private key is the SPARKLE_PRIVATE_KEY secret.
	SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-bSmZgoKFOnXOCuDdVdUvmpiK0PznPq1sUJkqThyghko=}"
	# shellcheck disable=SC2086
	swift build -c release --arch arm64 --arch x86_64 $RPATH >&2
	BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
else
	BUNDLE_ID="io.github.sypion.jf-dp.dev"
	# shellcheck disable=SC2086
	swift build $RPATH >&2
	BIN_DIR="$(swift build --show-bin-path)"
fi

APP="build/jf-dp.app"
CONTENTS="$APP/Contents"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"

cp "$BIN_DIR/JFDP" "$CONTENTS/MacOS/jf-dp"
ditto "$BIN_DIR/Sparkle.framework" "$CONTENTS/Frameworks/Sparkle.framework"
cp packaging/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"

# LSUIElement: a menu bar app, with no Dock icon.
# NSAllowsArbitraryLoads: home servers are mostly plain http, on IPs or names ATS doesn't treat as local.
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>jf-dp</string>
	<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
	<key>CFBundleName</key><string>jf-dp</string>
	<key>CFBundleDisplayName</key><string>jf-dp</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
	<key>LSApplicationCategoryType</key><string>public.app-category.entertainment</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSUIElement</key><true/>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsArbitraryLoads</key><true/>
	</dict>
	<key>NSLocalNetworkUsageDescription</key><string>jf-dp connects to your Jellyfin server to see what you're playing.</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<key>NSHumanReadableCopyright</key><string>Free software under the GNU GPL v3.</string>
	<key>SUFeedURL</key><string>${FEED_URL:-}</string>
	<key>SUPublicEDKey</key><string>${SPARKLE_PUBLIC_KEY:-}</string>
	<key>SUEnableAutomaticChecks</key><true/>
	<key>SUAutomaticallyUpdate</key><true/>
</dict>
</plist>
PLIST

IDENTITY="${SIGN_IDENTITY:--}"
SPARKLE="$CONTENTS/Frameworks/Sparkle.framework/Versions/B"

# Inside out: Sparkle's helpers, the framework, then the app.
for part in \
	"$SPARKLE/XPCServices/Installer.xpc" \
	"$SPARKLE/XPCServices/Downloader.xpc" \
	"$SPARKLE/Autoupdate" \
	"$SPARKLE/Updater.app" \
	"$CONTENTS/Frameworks/Sparkle.framework" \
	"$APP"; do
	[ -e "$part" ] || continue
	if [ "$IDENTITY" = "-" ]; then
		codesign --force --sign - "$part"
	else
		codesign --force --timestamp --options runtime --sign "$IDENTITY" "$part"
	fi
done

codesign --verify --deep --strict "$APP"
echo "$APP"
