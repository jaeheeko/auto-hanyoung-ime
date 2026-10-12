# Hanyoung (한영) — 한영 전환키 없는 macOS 한국어 입력기

> **An experimental macOS input method that removes the Korean/English toggle key.** You just type; each word is classified as Korean, English, or English + Korean particle (e.g. `Slack에서`) by a small on-device character n-gram model, and rendered accordingly. No cloud, no neural network, sub-millisecond decisions. Korean documentation follows.

한영 전환을 깜빡해서 `gksrmf`을 지우고 `한글`을 다시 치는 일을 없애려고 만든 입력기입니다. 전환키를 누르지 않고 그냥 타이핑하면, 어절(공백 사이 덩어리)마다 입력기가 **한국어 / 영어 / 영어+조사**를 판정해서 자동으로 변환합니다.

- 판정은 전부 로컬에서, 어절당 0.4ms 안에 끝납니다. 네트워크도 신경망도 없습니다.
- 틀리면 **오른쪽 ⌘를 한 번 톡** 칩니다. 방금 어절이 반대 언어로 바뀌고, 그 단어는 사용자 사전에 학습됩니다.
- 개인용으로 만들어 매일 쓰고 있는 단계입니다. 서명·공증·배포는 되어 있지 않아 직접 빌드해야 합니다.

## 어떻게 동작하나

사용자는 언제나 같은 물리 키를 누르므로, 문제는 "이 키열이 한국어를 의도한 것인가 영어를 의도한 것인가"를 고르는 분류입니다. 어절 하나에 대해 세 가설의 점수를 비교합니다.

| 가설 | 예 (`keys` → 결과) | 점수 |
|---|---|---|
| `KO` 전체를 두벌식으로 | `gksrmf` → 한글 | 한국어 키열 문자 5-gram + 어휘 사전 − 단독 자모·Shift 위반 벌점 |
| `EN` 전체를 영어로 | `hello` → hello | 영어 문자 5-gram + 어휘 사전 |
| `EN+KO(i)` 앞은 영어, 뒤는 한국어 | `Slackdptj` → Slack에서 | 영어 접두 + 조사·어미 전용 n-gram, 분할점마다 하나의 가설 |

여기에 직전 어절의 언어, 앱별 기본값(터미널·에디터는 영어 쪽), 사용자 사전을 사전확률로 더합니다. `ㅋㅋ`·`ㅠㅠ`·`굿ㅋㅋ` 같은 자모 관용 표현은 별도 규칙으로 처리합니다.

타이핑 중에는 1위 가설을 조합 중 글자(밑줄)로 보여 주고, 스페이스·문장부호·엔터에서 확정합니다. 이미 확정된 글자를 지우고 다시 쓰는 일이 없어서 어떤 앱에서도 안전합니다. 표시가 매 타 깜빡이지 않도록 다른 가설이 충분히 앞설 때만 표시를 바꿉니다(히스테리시스).

개인 노트 92만 어절로 평가했을 때 어절 정확도 99.92%, 혼합 어절(`API를` 류) 99.5%, 타이핑 중 2타 이후 표시 안정성 99.3%였습니다. 남는 오류는 대부분 `so/내`, `to/새`처럼 어절 하나로는 결정할 수 없는 양의성입니다.

## 요구 사항

- macOS 13 이상 (Apple Silicon·Intel), Xcode 또는 Command Line Tools (Swift 5.9+)
- Python 3.10 이상 (표준 라이브러리만 사용)
- 한국어·영어가 섞인 **본인의 글** 수십만 어절. 모델은 저장소에 포함되지 않습니다(아래 참고).

## 설치

### 1. 모델 만들기

모델은 학습한 문서의 어휘를 그대로 담기 때문에 저장소에 올리지 않습니다. 본인의 노트, 메시지 내보내기, 블로그 원고 등 `.md`/`.txt`가 들어 있는 폴더로 직접 만듭니다. 한국어·영어가 자연스럽게 섞인 글일수록 좋습니다.

```bash
./scripts/fetch_external.sh                       # 영어 단어 빈도표 내려받기 (CC BY-SA 4.0)
python3 -I tools/corpus.py ~/Documents/notes      # data/train.tsv, data/test.tsv
python3 -I tools/evaluate.py --save               # 학습 + 정확도 리포트, models/hanyoung.pkl
python3 -I tools/export_model.py                  # models/hanyoung.json (앱이 읽는 파일)
python3 -I tools/make_vectors.py                  # Swift 일치 검증용 벡터
swift test                                        # Python과 Swift 판정이 같은지 확인
```

`evaluate.py`가 어절 정확도와 오분류 목록(`data/errors.tsv`)을 출력합니다. 99% 아래라면 코퍼스가 너무 적거나 한쪽 언어로 치우친 경우입니다.

### 2. 빌드·설치

```bash
./scripts/build.sh      # build/Hanyoung.app (ad-hoc 서명)
./scripts/install.sh    # ~/Library/Input Methods 에 설치하고 입력 소스로 등록
```

메뉴 막대 입력 메뉴에서 **한영 자동**을 고릅니다. 목록에 없으면 시스템 설정 › 키보드 › 입력 소스에서 한국어 아래를 확인하거나, 로그아웃 후 다시 로그인합니다.

## 사용

- 전환키 없이 그냥 칩니다. 스페이스·문장부호·엔터·방향키에서 어절이 확정됩니다.
- **오른쪽 ⌘ 톡** = 되돌리기. 조합 중이면 조합 중 어절의 언어를 바꾸고, 확정 직후면 그 어절을 바꿉니다. 바뀐 단어는 사용자 사전에 학습됩니다.
- ⌘·⌃·⌥ 조합키는 입력기가 건드리지 않고 그대로 통과합니다.
- 믿을 만해지면 다른 한국어 입력 소스와 ABC를 끄는 것을 권합니다. 그래야 Caps Lock이 입력 소스 전환으로 새지 않습니다.

### 설정

`~/Library/Application Support/Hanyoung/`

| 파일 | 내용 |
|---|---|
| `config.json` | 앱별 가중치 `appBias`(번들 ID → `{"EN": 3.0}`), 자동 판정을 끌 앱 `disabledApps`, 표시 히스테리시스 `hysteresis`, 되돌리기 키 `toggleKeyCode`(54 = 오른쪽 ⌘, 61 = 오른쪽 ⌥) |
| `user_dict.json` | 되돌리기로 학습한 단어 |
| `log.jsonl` | 판정·되돌리기 로그. 로컬에만 남고 재학습 분석에 씁니다 |

### 판정 확인

```bash
python3 -I tools/classify.py gksrmf Slackdptj so --prev KO
```

## 구조

```
tools/              Python. 코퍼스 추출 → n-gram 학습 → 평가 → 모델 JSON 내보내기
Sources/Engine/     Swift. 두벌식 오토마타, 문자 n-gram, 판정기. Python과 동작이 같아야 한다
Sources/Hanyoung/   InputMethodKit 입력기 앱
Tests/EngineTests/  Python이 만든 벡터로 Swift 구현의 일치를 검증
scripts/            빌드·설치·등록·아이콘
```

판정 로직은 Python으로 먼저 만들고 평가한 뒤 Swift로 옮기며, `make_vectors.py`가 만든 벡터로 두 구현이 소수점까지 같은지 테스트합니다. 모델을 바꿀 때는 Python에서 평가하고 Swift에 반영하는 순서입니다.

## 알려진 한계

- 숫자·`_`·`/`가 섞인 토큰은 그 문자에서 어절이 끊깁니다. `snake_case`는 `snake`, `case`로 나뉘어 각각 판정됩니다.
- `so/내`, `to/새`, `the/솓`처럼 양쪽 다 흔한 짧은 어절은 문맥 사전확률과 사용자 사전에 의존합니다.
- 되돌리기는 커서 바로 앞이 방금 확정한 어절일 때, 그리고 앱이 텍스트 교체(`replacementRange`)를 지원할 때만 동작합니다.
- `dkzz`는 Apple 두벌식과 같이 `앜ㅋ`로 조립됩니다.
- 세벌식, 한자 변환, 자동 완성은 지원하지 않습니다.

## 참고 자료

- 영어 단어 빈도표: [hermitdave/FrequencyWords](https://github.com/hermitdave/FrequencyWords) (CC BY-SA 4.0). 모델 학습에만 쓰이며 저장소에 포함되지 않습니다.
- 영어 사전: macOS `/usr/share/dict/words`
- 같은 문제를 러시아어·영어에서 풀어 온 Punto Switcher, Caramba Switcher에서 "틀리면 한 키로 되돌린다"는 발상을 가져왔습니다.

## 라이선스

[MIT](LICENSE)
