#!/bin/bash
# build/Hanyoung.app을 ~/Library/Input Methods에 설치하고 입력 소스로 등록·활성화한다.
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="$HOME/Library/Input Methods"
mkdir -p "$DEST"
# 새 번들을 먼저 제자리에 바꿔 넣고 나서 프로세스를 끝낸다. 사용자가 타이핑 중이면 시스템이
# pkill 직후 즉시 다시 띄우는데, 그때 옛 번들이 남아 있으면 옛 버전이 올라온다.
rm -rf "$DEST/Hanyoung.app.new" "$DEST/Hanyoung.app.old"
cp -R build/Hanyoung.app "$DEST/Hanyoung.app.new"
[ -d "$DEST/Hanyoung.app" ] && mv "$DEST/Hanyoung.app" "$DEST/Hanyoung.app.old"
mv "$DEST/Hanyoung.app.new" "$DEST/Hanyoung.app"
pkill -x Hanyoung 2>/dev/null || true
rm -rf "$DEST/Hanyoung.app.old"
echo "installed: $DEST/Hanyoung.app"

swiftc -O -o build/register scripts/register.swift -framework Carbon 2>/dev/null || swiftc -o build/register scripts/register.swift -framework Carbon
# Launch Services가 build/Hanyoung.app까지 같은 번들 ID로 알고 있으면 시스템이 서버를 못 띄운다. 설치본만 남긴다.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -u "$PWD/build/Hanyoung.app" >/dev/null 2>&1 || true
"$LSREGISTER" -f "$DEST/Hanyoung.app" >/dev/null 2>&1 || true
# 서버를 끝내면 시스템이 ABC로 넘어갈 때가 있어 이 입력기를 다시 선택한다. 서버는 다음 키 입력 때 시스템이 띄운다.
# `open`으로 직접 띄우면 안 된다: 그 인스턴스는 시스템 연결을 못 받아 키가 전혀 들어오지 않는다.
build/register "$DEST/Hanyoung.app" --select
echo "선택됨: Auto HanYoung. 아무 곳에나 타이핑하면 서버가 뜬다. 확인: pgrep -x Hanyoung"
