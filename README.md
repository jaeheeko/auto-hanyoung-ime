# Auto HanYoung — 한영 전환키를 없앤 macOS 한국어 입력기

> **A macOS input method that makes the Korean/English toggle key unnecessary.** Just type. Each word is classified on-device as Korean, English, or English + Korean particle (`Slack에서`) and rendered accordingly. No cloud, no neural network, 0.4 ms per word. Korean documentation follows.

## 왜 만들었나

한영 키를 분명히 눌렀는데 씹혀서 `gksrmf`이 찍힙니다. 창 몇 개를 오가다 보면 지금 어느 언어인지 꼬여서 또 틀립니다. 그때마다 지우고 다시 칩니다. 한국인이라면 평생 수십 시간을 이 짓에 쓰고, 그만큼 빡칩니다.

이 입력기는 그 시간을 없앱니다. **전환키를 아예 누르지 않고 그냥 타이핑하면**, 어절(공백 사이 덩어리)마다 입력기가 한국어인지 영어인지 영어+조사인지 판정해서 알아서 바꿔 줍니다. 지금 어느 언어 상태인지 신경 쓸 필요가 없어집니다.

```
gksrmfdmf Tmqslek    →  한글을 씁니다
hello                →  hello
Slackdptj qhkTdjdy   →  Slack에서 봤어요
```

## 무엇이 좋은가

- **전부 로컬.** 네트워크도 신경망도 없고 어절당 0.4ms 안에 끝나 타이핑이 밀리지 않습니다. 메모리 약 50MB.
- **설치하면 바로 씁니다.** 공개 코퍼스로 학습한 기본 모델이 들어 있고, `html`·`sql`·`sdk` 같은 개발 용어도 압니다. 한영 혼용 노트 10만 어절로 재 보면 어절 정확도 99.9%, 본인 문서로 개인화하면 99.97%입니다(오류 1/3,300어절).
- **한/영 키 습관과 싸우지 않습니다.** 누르던 대로 눌러도 되고, 안 누르면 자동입니다. 누른 쪽이 손해 보는 경우가 없게 만들었습니다.
- **틀리면 톡 두 번.** 방금 어절이 반대 언어로 바뀌고, 그 단어는 한 번 고치면 다음부터 맞게 나옵니다. `db`를 영어로 고치면 `db에서`, `db로`, `DB`도 같이 맞습니다.

## 설치

macOS 13 이상, Apple Silicon·Intel 모두. Apple 공증은 되어 있지 않습니다.

**AI에게 맡기기 (권장)**: Claude Code, Codex, Gemini CLI처럼 터미널을 쓸 수 있는 AI에게 아래 한 줄을 붙여 넣습니다. 내려받기·검증·설치·입력 소스 등록까지 AI가 하고, 끝나면 되돌리기 키 사용법을 알려 줍니다.

```
https://raw.githubusercontent.com/jaeheeko/auto-hanyoung-ime/main/INSTALL.md 를 읽고 그대로 따라서 Auto HanYoung을 설치해 줘.
```

**직접 한 줄로**: 터미널에서 아래를 실행합니다. [Releases](https://github.com/jaeheeko/auto-hanyoung-ime/releases)의 zip을 받아 설치하고 입력 소스로 등록·선택합니다. 로그아웃이 필요 없습니다. 같은 스크립트에 `--uninstall`을 주면 지웁니다.

```bash
curl -fsSL https://raw.githubusercontent.com/jaeheeko/auto-hanyoung-ime/main/scripts/install-release.sh | bash
```

**직접 빌드** (Xcode 또는 Command Line Tools 필요):

```bash
git clone https://github.com/jaeheeko/auto-hanyoung-ime.git && cd auto-hanyoung-ime
./scripts/build.sh      # 기본 모델을 내려받고(최초 1회, 26 MB) 앱을 만든다
./scripts/install.sh    # 설치하고 입력 소스로 등록·선택한다
```

설치가 끝나면 메뉴 막대 입력 메뉴에 **Auto HanYoung**이 선택되어 있습니다. 믿을 만해지면 다른 한국어 입력 소스와 ABC는 끄는 것을 권합니다.

오른쪽 ⌘를 F18로 바꿔 한/영 키로 쓰고 있었다면(hidutil·Karabiner 사용자에게 흔한 설정) 시스템 설정 › 키보드 › 키보드 단축키 › 입력 소스에서 "이전/다음 입력 소스 선택"을 끕니다. 그 키가 그대로 이 입력기의 되돌리기 키가 됩니다.

## 사용

그냥 칩니다. 스페이스·문장부호·엔터에서 어절이 확정됩니다. 타이핑 중에는 판정 결과가 밑줄로 보입니다.

한/영 키(오른쪽 ⌘ 또는 F18)는 상황에 따라 이렇게 동작합니다.

| 상황 | 동작 | 뜻 |
|---|---|---|
| 어절 중간 | 한 번 톡 | 여기서 언어가 바뀐다. `SK` 톡 `플래닛` → SK플래닛 |
| 어절 끝 또는 어절 사이 | 한 번 톡 | 다음 어절은 방금 친 언어의 반대로 시작한다. 톡 뒤에 스페이스를 쳐도 유지되고, 그 한 어절에만 적용된다 |
| 어절 사이 | **두 번 톡** | 방금 어절(또는 커서가 닿은 어절)을 다른 언어로. 연타하면 계속 돈다 |
| 글자를 선택한 뒤 | 한 번 톡 | 선택한 글자만 반대 언어로 |

한 번 톡하면 커서 옆에 다음 글자의 언어가 `A` 또는 `한`으로 잠깐 보입니다.

**지우고 다시 쳐도 됩니다.** 틀린 어절을 백스페이스로 지우고 같은 키를 다시 치면 다른 언어로 바뀝니다. 한 번 더 지우고 다시 치면 그다음 가설로 넘어갑니다. 영어였다면 한국어로, 한국어였다면 영어로 먼저 바뀝니다. 원래 판정이 아슬아슬했던 어절에만 적용되고(`hello`처럼 확실한 어절은 그대로), 바뀐 어절을 그대로 두고 다음 어절로 넘어가면 한/영 키로 고친 것과 똑같이 학습됩니다.

고친 어절은 사용자 사전에 학습되어 조사가 붙은 변형과 대문자 변형에도 적용됩니다.

### 개인화 (선택)

본인 노트·메시지·원고가 든 폴더로 어휘 사전을 만듭니다. 문서 내용은 저장되지 않고 어절 빈도만 남습니다. Python 3.10 이상, 표준 라이브러리만 씁니다.

```bash
python3 -I tools/personalize.py ~/Documents/notes
```

### 설정

`~/Library/Application Support/Hanyoung/config.json`에서 앱별 기본값(`appBias`, 예: 터미널은 영어 쪽), 자동 판정을 끌 앱(`disabledApps`), 되돌리기 키(`toggleKeyCodes`), 지우고 다시 치기가 발동할 판정 격차 상한(`retypeMargin`, 기본 10, 0이면 끔)을 바꿀 수 있습니다. 판정 로그는 같은 폴더의 `log.jsonl`에 로컬로만 남습니다.

## 알려진 한계

- `so/내`, `to/새`처럼 양쪽 다 흔한 짧은 어절은 문맥에 의존합니다. 틀리면 톡 두 번.
- 숫자·`_`·`/`가 섞인 토큰은 그 문자에서 어절이 끊깁니다.
- 선택 영역 변환은 터미널에서는 동작하지 않습니다.
- 세벌식, 한자 변환은 지원하지 않습니다.

## 라이선스

코드는 [MIT](LICENSE). 기본 모델은 [NSMC](https://github.com/e9t/nsmc)(CC0), [KorNLI](https://github.com/kakaobrain/kor-nlu-datasets)(CC BY-SA 4.0), [KLUE YNAT](https://github.com/KLUE-benchmark/KLUE)(CC BY-SA 4.0), [FrequencyWords](https://github.com/hermitdave/FrequencyWords)(CC BY-SA 4.0)의 어절 빈도에 [Stack Overflow 태그](https://api.stackexchange.com/)(CC BY-SA 4.0)와 [GitHub Linguist](https://github.com/github-linguist/linguist)(MIT)의 기술 어휘를 더해 만들어 CC BY-SA 4.0을 따릅니다. 틀리면 한 키로 되돌린다는 발상은 Punto Switcher에서 가져왔습니다.
