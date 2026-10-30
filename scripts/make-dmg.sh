#!/bin/bash
# Packages the Release build as build.noindex/Marked.dmg. Run through `make dmg`.
set -euo pipefail

derived=build.noindex
app="$derived/Build/Products/Release/Marked.app"
output="$derived/Marked.dmg"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

ditto --norsrc --noextattr "$app" "$stage/Marked.app"

# Licenses that have to travel with compiled copies.
licenses="$stage/Marked.app/Contents/Resources/Licenses"
mkdir -p "$licenses"
cp LICENSE "$licenses/Marked-LICENSE.txt"
cp "$derived/SourcePackages/checkouts/swift-cmark/COPYING" "$licenses/swift-cmark-COPYING.txt"

# Release builds keep debug info that holds absolute source paths, including the
# builder's home folder. Strip it, then re-sign, since stripping breaks the signature.
strip -S -x "$stage/Marked.app/Contents/MacOS/Marked"
codesign --force --sign - "$stage/Marked.app"
codesign --verify --strict "$stage/Marked.app"

if LC_ALL=C grep -a -q -r "/Users/" "$stage/Marked.app"; then
    echo "error: a local path is still inside Marked.app, refusing to package it" >&2
    exit 1
fi

ln -s /Applications "$stage/Applications"
cat > "$stage/How to open Marked.txt" <<'TXT'
1. Drag Marked to the Applications folder.
2. Open Marked. macOS says it can't verify the app, because Marked isn't
   notarized by Apple. Click Done.
3. Open System Settings > Privacy & Security, scroll down, and click Open Anyway.

You only need to do this once.
TXT

rm -f "$output"
hdiutil create -quiet -volname Marked -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$output"
echo "Wrote $output"
