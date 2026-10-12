"""Swift Engine 동작 일치 검증용 벡터 생성.

Tests/vectors/automaton.tsv : keys \t 조립 결과 \t lone \t shift_bad   (모델 무관, 저장소에 포함)
Tests/vectors/decide.tsv    : keys \t prev \t final \t label \t text \t KO \t EN \t MIX  (모델에 따라 다름, 로컬 생성)

벡터는 아래 고정 목록에서만 만든다. 학습 데이터의 어휘가 저장소에 섞여 들어가지 않게 하기 위해서다.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from classify import load  # noqa: E402
from hangul import compose, to_keys  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "Tests", "vectors")

# 한국어 어절은 한글로 적고 키열로 변환한다
KOREAN = """
한글 안녕하세요 감사합니다 과기 완강라 깔 있습니다 값 물고기 가까 걔들한테 아니다 확인 원요크 귀
오늘 내일 회의 프로젝트 일정 공유 부탁드립니다 확인했습니다 좋아요 괜찮아요 고생하셨습니다 점심 저녁
사람 생각 시간 문제 방법 결과 시작 마지막 다음 이번 지난 때문에 그래서 하지만 그리고 또는 않았다 됐다
밥 먹었어요 뭐해 어디야 언제 왜 누가 얼마나 빨리 천천히 많이 조금 아주 정말 진짜 완전 대박 헐 와
읽기 쓰기 듣기 말하기 컴퓨터 키보드 마우스 화면 소리 사진 영상 음악 책 노트 기록 메모 일기 편지
서울 부산 대한민국 한국어 영어 일본어 중국어 숫자 문자 단어 문장 문단 글 뜻 소리 모양 색깔 크기
닭 삶 값 몫 않 핥 읊 끓 밟 옮 뚫 꺾 쫓 뺏 옆 밖 앉 많 흙 삯 곬 돐
""".split()
JAMO = "ㅋㅋ ㅎㅎ ㅠㅠ ㅜㅜ ㅋㅋㅋㅋㅋㅋㅋㅋㅋㅋ ㅎ ㅇㅇ ㅇㅋ ㄱㄱ ㄷㄷ ㄲㅂ ㅗㅜㅑ 굿ㅋㅋ 앜ㅋ ㅋㅋ굿 싶어요ㅠㅠ 진짜ㅠㅠ 부엌칼 ㅋㅋㅠㅠ".split()
ENGLISH = """
Hello hello the so to a I is of in it on we he be me no do go did had egg mm BBB Then then
git status standup skip git commit push pull merge rebase branch main master origin remote
API SDK URL JSON HTTP CPU GPU macOS iOS Swift Python Kotlin React Slack Obsidian Chrome Xcode
meeting schedule project deadline review feedback launch release version update design
camelCase snakeCase PascalCase kebab Temasek Arns CJ KB SNS ID RQ Eh cor Wnt al
""".split()
MIXED = "Slack에서 API를 CJ올리브영 A군은 G마켓에서 standup은 skip할게요 Slack이 URL은 iPhone으로 Python으로는 SDK의 KB스타뱅킹".split()
PREFIXES = "a r d dk dks dkss dkssu dkssud T Ekqhd hkkk mlml x zzr rntz 2qjs".split()


def mixed_keys(token: str) -> str:
    i = 0
    while i < len(token) and token[i].isascii():
        i += 1
    return token[:i] + to_keys(token[i:])


def fmt(v):
    return "-inf" if v == float("-inf") else f"{v:.6f}"


def main():
    keys_list = [to_keys(w) for w in KOREAN] + [to_keys(w) for w in JAMO] + ENGLISH \
        + [mixed_keys(w) for w in MIXED] + PREFIXES + [""]
    os.makedirs(OUT, exist_ok=True)

    with open(os.path.join(OUT, "automaton.tsv"), "w") as f:
        for keys in keys_list:
            text, lone, bad = compose(keys)
            f.write(f"{keys}\t{text}\t{lone}\t{bad}\n")

    clf = load(os.path.join(ROOT, "models", "hanyoung.pkl"))
    n = 0
    with open(os.path.join(OUT, "decide.tsv"), "w") as f:
        for keys in keys_list:
            if not keys:
                continue
            for prev in ("BR", "KO", "EN"):
                for final in (True, False):
                    d = clf.decide(keys, prev=prev, final=final)
                    f.write(f"{keys}\t{prev}\t{int(final)}\t{d.label}\t{d.text}\t"
                            f"{fmt(d.scores['KO'])}\t{fmt(d.scores['EN'])}\t{fmt(d.scores['MIX'])}\n")
                    n += 1
    print(f"Tests/vectors/automaton.tsv ({len(keys_list)}), decide.tsv ({n}) 생성")


if __name__ == "__main__":
    main()
