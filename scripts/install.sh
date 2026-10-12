#!/bin/bash
# build/Hanyoung.app을 ~/Library/Input Methods에 설치하고 입력 소스로 등록·활성화한다.
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="$HOME/Library/Input Methods"
mkdir -p "$DEST"
pkill -x Hanyoung 2>/dev/null || true
sleep 0.3
rm -rf "$DEST/Hanyoung.app"
cp -R build/Hanyoung.app "$DEST/Hanyoung.app"
echo "installed: $DEST/Hanyoung.app"

swiftc -O -o build/register scripts/register.swift -framework Carbon 2>/dev/null || swiftc -o build/register scripts/register.swift -framework Carbon
build/register "$DEST/Hanyoung.app"
