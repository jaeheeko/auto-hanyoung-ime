#!/bin/bash
# 릴리스 빌드 후 build/Hanyoung.app 번들을 조립하고 ad-hoc 서명한다.
# models/hanyoung.json이 없으면 GitHub Release의 기본 모델(공개 코퍼스로 학습)을 내려받는다.
set -euo pipefail
cd "$(dirname "$0")/.."

MODEL_URL=${HANYOUNG_MODEL_URL:-https://github.com/jaeheeko/hanyoung-ime/releases/download/model-v1/hanyoung.json}
if [ ! -s models/hanyoung.json ]; then
  echo "models/hanyoung.json 없음 → 기본 모델 내려받기: $MODEL_URL"
  mkdir -p models
  curl -fL --progress-bar --max-time 600 -o models/hanyoung.json.part "$MODEL_URL"
  mv models/hanyoung.json.part models/hanyoung.json
fi

swift build -c release --product Hanyoung

APP=build/Hanyoung.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Hanyoung "$APP/Contents/MacOS/Hanyoung"
cp Sources/Hanyoung/Info.plist "$APP/Contents/Info.plist"
cp models/hanyoung.json "$APP/Contents/Resources/hanyoung.json"
[ -f assets/menu.tiff ] && cp assets/menu.tiff "$APP/Contents/Resources/menu.tiff"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --deep --sign - "$APP"
echo "built: $APP"
