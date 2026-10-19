#!/bin/bash
# GitHub Release의 Auto HanYoung을 내려받아 설치하고 입력 소스로 등록·선택한다. 저장소를 받을 필요도, Xcode도 필요 없다.
#
#   bash install-release.sh              # 최신 릴리스
#   bash install-release.sh v0.1.6       # 특정 버전
#   bash install-release.sh --dry-run    # 내려받고 검증만 하고 설치는 하지 않는다
#   bash install-release.sh --uninstall  # 지운다
#
# 환경변수 HANYOUNG_ZIP=<파일>을 주면 내려받지 않고 그 zip을 설치한다.
set -euo pipefail

REPO=jaeheeko/auto-hanyoung-ime
DEST="$HOME/Library/Input Methods"
APP="$DEST/Hanyoung.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

TAG=latest; DRY=0; UNINSTALL=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    v*) TAG=$a ;;
    *) echo "모르는 인자: $a" >&2; exit 2 ;;
  esac
done

fail() { printf "오류: %b\n" "$*" >&2; exit 1; }

if [ "$UNINSTALL" = 1 ]; then
  [ -d "$APP" ] || { echo "설치되어 있지 않다: $APP"; exit 0; }
  "$APP/Contents/MacOS/register" "$APP" --disable 2>/dev/null || true
  pkill -x Hanyoung 2>/dev/null || true
  rm -rf "$APP"
  "$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
  echo "지웠다: $APP (입력 메뉴에서 사라지지 않으면 로그아웃 후 로그인)"
  echo "학습한 사전과 설정은 남겨 두었다: ~/Library/Application Support/Hanyoung"
  exit 0
fi

[ "$(uname -s)" = Darwin ] || fail "macOS 전용이다."
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
[ "$MAJOR" -ge 13 ] || fail "macOS 13 이상이 필요하다 (현재 $(sw_vers -productVersion))."

WORK=$(mktemp -d -t hanyoung-install)
trap 'rm -rf "$WORK"' EXIT

if [ -n "${HANYOUNG_ZIP:-}" ]; then
  ZIP=$HANYOUNG_ZIP
  echo "로컬 zip 사용: $ZIP"
else
  if [ "$TAG" = latest ]; then
    TAG=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
    [ -n "$TAG" ] || fail "최신 릴리스를 확인하지 못했다. 네트워크를 확인하거나 버전을 직접 지정한다 (예: v0.1.6)."
  fi
  VER=${TAG#v}
  BASE="https://github.com/$REPO/releases/download/$TAG"
  ZIP="$WORK/Auto-HanYoung-$VER.zip"
  echo "내려받기: $BASE/Auto-HanYoung-$VER.zip"
  curl -fL --progress-bar -o "$ZIP" "$BASE/Auto-HanYoung-$VER.zip" || fail "zip을 내려받지 못했다: $TAG"
  if curl -fsL -o "$ZIP.sha256" "$BASE/Auto-HanYoung-$VER.zip.sha256"; then
    EXPECT=$(awk '{print $1}' "$ZIP.sha256")
    ACTUAL=$(shasum -a 256 "$ZIP" | awk '{print $1}')
    [ "$EXPECT" = "$ACTUAL" ] || fail "sha256이 다르다. 받은 파일이 손상됐거나 바뀌었다.\n  기대: $EXPECT\n  실제: $ACTUAL"
    echo "sha256 확인: $ACTUAL"
  else
    echo "sha256 파일이 없는 릴리스다. 검증 없이 진행: $(shasum -a 256 "$ZIP" | awk '{print $1}')"
  fi
fi

ditto -x -k "$ZIP" "$WORK/unzipped" || fail "zip을 풀지 못했다."
SRC=$(find "$WORK/unzipped" -maxdepth 2 -name Hanyoung.app -type d | head -1)
[ -n "$SRC" ] || fail "zip 안에 Hanyoung.app이 없다."
[ -x "$SRC/Contents/MacOS/Hanyoung" ] || fail "번들이 깨져 있다."
[ -x "$SRC/Contents/MacOS/register" ] || fail "이 릴리스에는 등록 도우미가 없다. v0.1.6 이상을 설치한다."
xattr -dr com.apple.quarantine "$SRC" 2>/dev/null || true
BUNDLE_VER=$(defaults read "$SRC/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?")
ARCHS=$(lipo -archs "$SRC/Contents/MacOS/Hanyoung" 2>/dev/null || echo "?")
echo "번들: Auto HanYoung $BUNDLE_VER ($ARCHS), 이 Mac은 $(uname -m)"
case " $ARCHS " in *" $(uname -m) "*) ;; *) fail "이 Mac($(uname -m))용 바이너리가 아니다." ;; esac

if [ "$DRY" = 1 ]; then
  echo "dry-run: 설치하지 않았다. 설치하면 $APP 에 들어간다."
  exit 0
fi

mkdir -p "$DEST"
# 새 번들을 제자리에 바꿔 넣은 뒤 프로세스를 끝낸다. 시스템이 바로 다시 띄워도 새 버전이 올라오게.
rm -rf "$APP.new" "$APP.old"
cp -R "$SRC" "$APP.new"
[ -d "$APP" ] && mv "$APP" "$APP.old"
mv "$APP.new" "$APP"
pkill -x Hanyoung 2>/dev/null || true
rm -rf "$APP.old"
echo "설치: $APP"

"$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true
# 입력 소스로 등록·활성화하고 현재 입력 소스로 선택한다. 서버는 다음 키 입력 때 시스템이 띄운다.
if "$APP/Contents/MacOS/register" "$APP" --select; then
  echo
  echo "끝. 메뉴 막대 입력 메뉴에 'Auto HanYoung'이 보이고 지금 선택되어 있다. 아무 곳에나 타이핑하면 된다."
else
  echo
  echo "파일은 설치됐지만 입력 소스 등록이 바로 되지 않았다. 로그아웃 후 로그인하면 시스템 설정 › 키보드 › 입력 소스에 'Auto HanYoung'이 나타난다." >&2
  exit 3
fi
