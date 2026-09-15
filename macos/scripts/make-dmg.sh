#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

APP="$1"
DMG="$2"
VOLUME="jf-dp"

if [ -e "/Volumes/$VOLUME" ]; then
	echo "error: eject the \"$VOLUME\" disk first" >&2
	exit 1
fi

WORK="$(mktemp -d)"
MOUNT=""
cleanup() {
	if [ -n "$MOUNT" ]; then
		hdiutil detach "$MOUNT" -force -quiet || true
	fi
	rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

mkdir "$WORK/stage"
ditto "$APP" "$WORK/stage/jf-dp.app"
ln -s /Applications "$WORK/stage/Applications"
mkdir "$WORK/stage/.background"
cp packaging/dmg-background.tiff "$WORK/stage/.background/background.tiff"

hdiutil create -quiet -volname "$VOLUME" -srcfolder "$WORK/stage" -fs HFS+ -format UDRW "$WORK/rw.dmg"
MOUNT="$(hdiutil attach -readwrite -noverify -noautoopen "$WORK/rw.dmg" | sed -n 's|.*\(/Volumes/.*\)$|\1|p' | head -1)"

osascript packaging/dmg-layout.applescript "$VOLUME"

for _ in 1 2 3 4 5 6 7 8 9 10; do
	[ -f "$MOUNT/.DS_Store" ] && break
	sleep 1
done
rm -rf "$MOUNT/.fseventsd"
sync
hdiutil detach "$MOUNT" -quiet
MOUNT=""

rm -f "$DMG"
hdiutil convert -quiet "$WORK/rw.dmg" -format ULMO -o "$DMG"
echo "$DMG"
