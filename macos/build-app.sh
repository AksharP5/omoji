#!/usr/bin/env bash
# Builds omoji.app into macos/build with the shared catalog, search code, and strings.
set -euo pipefail

cd "$(dirname -- "$0")"
swift build -c release --product omoji
binary=$(swift build -c release --product omoji --show-bin-path)/omoji
app=build/omoji.app
version=$(sed -n 's/.*"version": "\(.*\)".*/\1/p' ../manifest.json)

rm -rf -- "$app"
mkdir -p -- "$app/Contents/MacOS" "$app/Contents/Resources"
cp -- "$binary" "$app/Contents/MacOS/omoji"
cp -- ../EmojiSearch.js ../emojis.json ../i18n/en.json "$app/Contents/Resources/"
sed "s/@VERSION@/$version/" Info.plist > "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "Built $PWD/$app"
