#!/bin/bash
# Builds build/NordvaMacEdge.app. With --install, copies it to /Applications and launches it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

app=build/NordvaMacEdge.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/NordvaMacEdge" "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/"
codesign --force --sign - "$app"
echo "built: $app"

if [[ "${1:-}" == "--install" ]]; then
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
