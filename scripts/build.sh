#!/bin/bash
# 릴리스 빌드 후 build/Hanyoung.app 번들을 조립하고 ad-hoc 서명한다.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Hanyoung

APP=build/Hanyoung.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Hanyoung "$APP/Contents/MacOS/Hanyoung"
cp Sources/Hanyoung/Info.plist "$APP/Contents/Info.plist"
cp models/hanyoung.json "$APP/Contents/Resources/hanyoung.json"
[ -f assets/menu.png ] && cp assets/menu.png "$APP/Contents/Resources/menu.png"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --deep --sign - "$APP"
echo "built: $APP"
