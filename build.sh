#!/bin/bash
# Собирает build/NordvaMacEdge.app. С флагом --install кладёт его в /Applications и запускает.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

app=build/NordvaMacEdge.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/NordvaMacEdge" "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/"
codesign --force --sign - "$app"
echo "собрано: $app"

if [[ "${1:-}" == "--install" ]]; then
    osascript -e 'quit app "NordvaMacEdge"' 2>/dev/null || true
    # quit возвращается сразу, а старая копия закрывается не мгновенно. Если открыть
    # новую раньше, macOS отдаст ошибку -600 и ничего не запустит.
    for _ in {1..50}; do
        pgrep -xq NordvaMacEdge || break
        sleep 0.1
    done
    pkill -x NordvaMacEdge 2>/dev/null || true
    rm -rf /Applications/NordvaMacEdge.app
    cp -R "$app" /Applications/
    open /Applications/NordvaMacEdge.app
    echo "установлено и запущено: /Applications/NordvaMacEdge.app"
fi
