#!/bin/bash
# Builds build/NordvaMacEdge.app.
#   --install  also copies it to /Applications and launches it
#   --release  builds a universal app (Apple Silicon + Intel) and packs it into
#              build/NordvaMacEdge.zip and build/NordvaMacEdge.dmg
set -euo pipefail
cd "$(dirname "$0")"

mode="${1:-}"
app=build/NordvaMacEdge.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"

if [[ "$mode" == "--release" ]]; then
    slices=()
    for triple in arm64-apple-macosx13.0 x86_64-apple-macosx13.0; do
        swift build -c release --triple "$triple"
        slices+=("$(swift build -c release --triple "$triple" --show-bin-path)/NordvaMacEdge")
    done
    lipo -create -output "$app/Contents/MacOS/NordvaMacEdge" "${slices[@]}"
else
    swift build -c release
    cp "$(swift build -c release --show-bin-path)/NordvaMacEdge" "$app/Contents/MacOS/"
fi
cp Resources/Info.plist "$app/Contents/"
mkdir -p "$app/Contents/Resources"
cp Resources/AppIcon.icns "$app/Contents/Resources/"

# An ad-hoc signature's requirement is its cdhash, so every rebuild would lose the
# Accessibility grant. Pinning the requirement to the bundle id keeps it across rebuilds.
codesign --force --sign - -r '=designated => identifier "io.github.orhan17.NordvaMacEdge"' "$app"
echo "built: $app"

if [[ "$mode" == "--release" ]]; then
    rm -f build/NordvaMacEdge.zip build/NordvaMacEdge.dmg
    ditto -c -k --keepParent "$app" build/NordvaMacEdge.zip
    echo "packed: build/NordvaMacEdge.zip"

    stage=build/dmg
    rm -rf "$stage"
    mkdir -p "$stage"
    cp -R "$app" "$stage/"
    ln -s /Applications "$stage/Applications"
    hdiutil create -quiet -volname NordvaMacEdge -srcfolder "$stage" -fs HFS+ -format UDZO -ov build/NordvaMacEdge.dmg
    rm -rf "$stage"
    echo "packed: build/NordvaMacEdge.dmg"
fi

if [[ "$mode" == "--install" ]]; then
    osascript -e 'quit app "NordvaMacEdge"' 2>/dev/null || true
    # `quit` returns immediately; opening the new copy before the old one exits fails with -600.
    for _ in {1..50}; do
        pgrep -xq NordvaMacEdge || break
        sleep 0.1
    done
    pkill -x NordvaMacEdge 2>/dev/null || true
    rm -rf /Applications/NordvaMacEdge.app
    cp -R "$app" /Applications/
    open /Applications/NordvaMacEdge.app
    echo "installed and launched: /Applications/NordvaMacEdge.app"
fi
