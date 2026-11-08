#!/usr/bin/env bash
# Builds omoji.app into macos/build with the shared catalog, search code, and strings.
set -euo pipefail

cd "$(dirname -- "$0")"
[[ $# -eq 0 || $1 == --dmg ]] || { echo "usage: $0 [--dmg]" >&2; exit 2; }
flags=(-c release --product omoji)
[[ "${1:-}" == --dmg ]] && flags+=(--arch arm64 --arch x86_64)
swift build "${flags[@]}"
binary=$(swift build "${flags[@]}" --show-bin-path)/omoji
app=build/omoji.app
version=$(sed -n 's/.*"version": "\(.*\)".*/\1/p' ../manifest.json)

rm -rf -- "$app"
mkdir -p -- "$app/Contents/MacOS" "$app/Contents/Resources"
cp -- "$binary" "$app/Contents/MacOS/omoji"
cp -- ../EmojiSearch.js ../emojis.json ../i18n/en.json "$app/Contents/Resources/"
iconset=$(mktemp -d)/AppIcon.iconset
swift make-icon.swift "$iconset"
iconutil -c icns -o "$app/Contents/Resources/AppIcon.icns" "$iconset"
rm -rf -- "$(dirname -- "$iconset")"
sed "s/@VERSION@/$version/" Info.plist > "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "Built $PWD/$app"

if [[ "${1:-}" == --dmg ]]; then
  staging=$(mktemp -d)
  cp -R -- "$app" "$staging/"
  ln -s /Applications "$staging/Applications"
  rm -f -- build/omoji.dmg
  hdiutil create -volname omoji -srcfolder "$staging" -format UDZO -o build/omoji.dmg
  rm -rf -- "$staging"
  echo "Built $PWD/build/omoji.dmg"
fi
