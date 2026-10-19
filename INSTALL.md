# Auto HanYoung 설치 안내 (AI 에이전트용)

> **For AI agents** (Claude Code, Codex CLI, Gemini CLI, Cursor, …) with shell access on the user's Mac: follow this document to install Auto HanYoung end to end. The user should not have to download, type, or click anything. Report back in the user's language. Korean follows.

이 문서는 사용자의 Mac에서 터미널을 쓸 수 있는 AI 에이전트가 읽고 그대로 실행하도록 쓴 것이다. 사용자가 직접 내려받거나 명령을 치거나 설정 창을 열지 않아도 끝나야 한다. 사람이 읽어도 된다.

## 0. 시작 전 확인

- macOS 13 이상이어야 한다. `sw_vers -productVersion`으로 확인한다. Apple Silicon과 Intel 모두 된다.
- 관리자 암호는 필요 없다. 파일은 `~/Library/Input Methods/Hanyoung.app` 한 곳에만 들어가고, 학습 사전·설정·로그는 `~/Library/Application Support/Hanyoung/`에 생긴다.
- 이미 Auto HanYoung을 쓰고 있는 사용자라면 설치 중 입력기 프로세스가 한 번 다시 시작되어 그 순간 치던 글자 한두 개가 씹힐 수 있다고 먼저 알린다. 처음 설치라면 영향 없다.
- 이 앱은 Apple 공증을 받지 않았고 ad-hoc 서명이다. 소스는 이 저장소에 MIT로 공개되어 있다. 사용자가 바이너리를 믿지 않으면 6절의 소스 빌드로 설치한다.

## 1. 설치

설치 스크립트를 받아서 읽고 실행한다. 저장소를 clone할 필요도, Xcode도 필요 없다.

```bash
curl -fsSL -o "$TMPDIR/hanyoung-install.sh" https://raw.githubusercontent.com/jaeheeko/auto-hanyoung-ime/main/scripts/install-release.sh
bash "$TMPDIR/hanyoung-install.sh"
```

스크립트가 하는 일: GitHub Releases에서 최신 zip과 `.sha256`을 받아 검증하고, 풀어서 `~/Library/Input Methods/`에 넣고, 번들 안의 `register` 도우미로 macOS 입력 소스에 등록·활성화한 뒤 현재 입력 소스로 선택한다. 로그아웃이 필요 없다.

- 특정 버전: `bash "$TMPDIR/hanyoung-install.sh" v0.1.6`
- 설치하지 않고 내려받기·검증만: `--dry-run`
- 종료 코드 `0` 성공, `1` 설치 전 실패(원인은 stderr에 한국어로 나온다), `3` 파일은 설치됐지만 입력 소스 등록이 안 됨(4절).

`open ~/Library/Input\ Methods/Hanyoung.app`으로 앱을 직접 띄우지 않는다. 그렇게 뜬 인스턴스는 시스템과 연결되지 않아 키가 전혀 들어오지 않는다. 입력기 서버는 사용자가 다음 키를 칠 때 시스템이 알아서 띄운다.

## 2. 설치 확인

1. `ls ~/Library/Input\ Methods/Hanyoung.app/Contents/MacOS/` 에 `Hanyoung`과 `register`가 있다.
2. 스크립트 출력에 `TISRegisterInputSource: ok`, `enable … enabled=true`, `select: ok`가 있다.
3. `defaults read com.apple.HIToolbox AppleSelectedInputSources | grep -c Hanyoung` 가 1 이상이다.
4. 사용자에게 메모나 TextEdit 같은 아무 글 입력란에서 `gksrmfdmf Tmqslek `를 쳐 보라고 한다(마지막 스페이스까지). `한글을 씁니다`가 나오면 끝이다. 이어서 `hello `는 그대로 `hello`, `Slackdptj `는 `Slack에서`가 된다.
5. 그 뒤 `pgrep -x Hanyoung`에 PID가 보인다. 아직 키를 안 쳤으면 안 보이는 게 정상이다.

에이전트 자신의 터미널에서는 테스트하지 않는다. 터미널 앱은 기본 설정이 영어 쪽으로 기울어 있어 결과가 다를 수 있다.

## 3. 사용자에게 알려 줄 것

설치가 끝나면 아래를 사용자 언어로 짧게 전한다. 길게 쓰지 말고 핵심만.

- **그냥 친다.** 한/영 키를 누르지 않아도 어절마다 한국어·영어·영어+조사(`Slack에서`)를 알아서 판정한다. 스페이스·문장부호·엔터에서 어절이 확정되고, 치는 동안 밑줄로 판정이 보인다.
- **틀리면 되돌리기 키.** 오른쪽 ⌘ 또는 F18이다.
  - 어절 사이에서 **두 번 톡**: 방금 어절이 반대 언어로 바뀌고 그 단어는 학습된다.
  - 어절 사이에서 **한 번 톡**: 다음 한 어절만 반대 언어로 시작한다. 커서 옆에 `A`/`한`이 잠깐 뜬다.
  - 어절 중간에서 한 번 톡: 거기서 언어가 바뀐다 (`SK` 톡 `플래닛`).
  - 글자를 선택하고 한 번 톡: 선택한 글자만 반대 언어로.
- **지우고 다시 쳐도 된다.** 틀린 어절을 백스페이스로 지우고 같은 키를 다시 치면 다른 언어로 바뀐다.
- **메뉴 막대 입력 메뉴**에 Auto HanYoung이 선택되어 있다. 며칠 써서 믿을 만해지면 시스템 설정 › 키보드 › 입력 소스에서 다른 한국어 입력기와 ABC를 빼는 것을 권한다. 이건 사용자가 직접 한다.

그리고 한 가지를 **물어본다**: 오른쪽 ⌘를 F18로 바꿔 한/영 키로 쓰고 있는가(hidutil·Karabiner 사용자에게 흔하다). 그렇다면 시스템 설정 › 키보드 › 키보드 단축키 › 입력 소스에서 "이전 입력 소스 선택"을 꺼야 한다. 켜져 있으면 그 키가 입력기를 바꿔 버려서 되돌리기 키로 동작하지 않는다. `defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys | grep -A3 '"60"'` 에서 `enabled = 1`이면 켜져 있는 것이다. 이 설정은 `defaults write`로 바꾸지 말고 사용자에게 창을 열어 끄라고 안내한다.

## 4. 문제 해결

| 증상 | 조치 |
|---|---|
| 입력 메뉴에 Auto HanYoung이 없다 (종료 코드 3) | 로그아웃 후 로그인. 그래도 없으면 시스템 설정 › 키보드 › 입력 소스 › 편집 › `+` › 한국어에서 추가 |
| 쳐도 아무 반응이 없다 | 메뉴 막대에서 Auto HanYoung이 선택됐는지 확인. `pgrep -x Hanyoung`이 비어 있으면 `pkill -x Hanyoung`은 하지 말고 다른 입력란에 몇 글자 쳐 본다 |
| "손상되었기 때문에 열 수 없습니다" 류의 경고 | `xattr -dr com.apple.quarantine ~/Library/Input\ Methods/Hanyoung.app` 뒤 `pkill -x Hanyoung` |
| 로그 보기 | `log show --predicate 'process == "Hanyoung"' --last 5m` |
| 영어로만 나온다 | 터미널 계열 앱은 기본값이 영어 쪽이다. 메모 앱에서 다시 시도 |

## 5. 업데이트와 삭제

- 업데이트: 1절의 스크립트를 다시 실행한다. 학습한 사전과 설정은 유지된다.
- 삭제: `bash "$TMPDIR/hanyoung-install.sh" --uninstall`. 입력 소스에서 빼고 앱을 지운다. `~/Library/Application Support/Hanyoung/`(사전·설정·로그)은 남기므로 완전히 지우려면 그 폴더도 지운다. 사용자 확인 없이 그 폴더를 지우지 않는다.

## 6. 선택 사항

**소스에서 빌드** (Xcode 또는 Command Line Tools 필요, 기본 모델 26MB를 받는다):

```bash
git clone https://github.com/jaeheeko/auto-hanyoung-ime.git && cd auto-hanyoung-ime
./scripts/build.sh && ./scripts/install.sh
```

**개인화.** 사용자의 노트·메시지·원고 폴더로 어휘 사전을 만들면 정확도가 올라간다(99.9% → 99.97%). 문서 내용은 저장되지 않고 어절 빈도만 남는다. 개인 문서를 읽는 일이므로 **사용자가 폴더를 지정하고 동의한 뒤에만** 실행한다. Python 3.10 이상, 표준 라이브러리만 쓴다.

```bash
git clone --depth 1 https://github.com/jaeheeko/auto-hanyoung-ime.git "$TMPDIR/hanyoung-src"
python3 -I "$TMPDIR/hanyoung-src/tools/personalize.py" ~/Documents/notes   # --dry-run으로 먼저 볼 수 있다
pkill -x Hanyoung   # 다음 키 입력 때 새 사전으로 다시 뜬다
```

**설정.** `~/Library/Application Support/Hanyoung/config.json`: 앱별 기본값 `appBias`, 자동 판정을 끌 앱 `disabledApps`, 되돌리기 키 `toggleKeyCodes`(기본 오른쪽 ⌘ 54, F18 79), 지우고 다시 치기 발동 상한 `retypeMargin`(기본 10, 0이면 끔). 바꾼 뒤 `pkill -x Hanyoung`.

## 7. 이 입력기가 하지 않는 것

네트워크를 쓰지 않는다. 판정은 전부 기기 안에서 끝나고, 판정 로그(`log.jsonl`)도 로컬에만 남는다. 세벌식과 한자 변환은 지원하지 않는다.
