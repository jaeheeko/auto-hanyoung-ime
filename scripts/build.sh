#!/bin/bash
# 릴리스 빌드 후 build/Hanyoung.app 번들을 조립하고 ad-hoc 서명한다. Apple Silicon·Intel 모두 도는 유니버설 바이너리다.
# models/hanyoung.model이 없으면 GitHub Release의 기본 모델(공개 코퍼스로 학습)을 내려받는다.
set -euo pipefail
cd "$(dirname "$0")/.."

MODEL_URL=${HANYOUNG_MODEL_URL:-https://github.com/jaeheeko/auto-hanyoung-ime/releases/download/model-v2/hanyoung.model}
if [ ! -s models/hanyoung.model ]; then
  echo "models/hanyoung.model 없음 → 기본 모델 내려받기: $MODEL_URL"
  mkdir -p models
  curl -fL --progress-bar --max-time 600 -o models/hanyoung.model.part "$MODEL_URL"
  mv models/hanyoung.model.part models/hanyoung.model
fi

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}" --product Hanyoung
BIN=$(swift build -c release "${ARCHS[@]}" --product Hanyoung --show-bin-path)

APP=build/Hanyoung.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Hanyoung" "$APP/Contents/MacOS/Hanyoung"
cp Sources/Hanyoung/Info.plist "$APP/Contents/Info.plist"
cp models/hanyoung.model "$APP/Contents/Resources/hanyoung.model"
[ -f assets/menu.tiff ] && cp assets/menu.tiff "$APP/Contents/Resources/menu.tiff"
[ -f assets/auto.pdf ] && cp assets/auto.pdf "$APP/Contents/Resources/auto.pdf"
cp -R Sources/Hanyoung/Resources/*.lproj "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# 입력 소스 등록 도우미를 번들에 같이 넣는다. 받아서 설치하는 쪽에는 swiftc가 없을 수 있다.
for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos13.0" -o "build/register-$arch" scripts/register.swift -framework Carbon
done
lipo -create -output "$APP/Contents/MacOS/register" build/register-arm64 build/register-x86_64
cp "$APP/Contents/MacOS/register" build/register
codesign --force --sign - "$APP/Contents/MacOS/register"
codesign --force --deep --sign - "$APP"
echo "built: $APP ($(lipo -archs "$APP/Contents/MacOS/Hanyoung"))"
