"""두벌식 자모 테이블, 음절→키, 키→음절 오토마타.

Swift Engine의 Hangul.swift와 동작이 같아야 한다. 테스트 벡터는 tests/automaton.tsv.
"""

CHO = "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ"
JUNG = "ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ"
JONG = "ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ"  # 인덱스 1부터

# 단일 키 → 자모 (두벌식). Shift가 의미 있는 키는 QWERT(쌍자음), OP(ㅒㅖ)뿐이다.
KEY_TO_JAMO = {
    "r": "ㄱ", "R": "ㄲ", "s": "ㄴ", "e": "ㄷ", "E": "ㄸ", "f": "ㄹ", "a": "ㅁ",
    "q": "ㅂ", "Q": "ㅃ", "t": "ㅅ", "T": "ㅆ", "d": "ㅇ", "w": "ㅈ", "W": "ㅉ",
    "c": "ㅊ", "z": "ㅋ", "x": "ㅌ", "v": "ㅍ", "g": "ㅎ",
    "k": "ㅏ", "o": "ㅐ", "i": "ㅑ", "O": "ㅒ", "j": "ㅓ", "p": "ㅔ", "u": "ㅕ",
    "P": "ㅖ", "h": "ㅗ", "y": "ㅛ", "n": "ㅜ", "b": "ㅠ", "m": "ㅡ", "l": "ㅣ",
}
SHIFT_KEYS = set("QWERTOP")

# 자모 → 키열 (복합 자모 포함)
JAMO_TO_KEYS = {j: k for k, j in KEY_TO_JAMO.items()}
JAMO_TO_KEYS.update({
    "ㅘ": "hk", "ㅙ": "ho", "ㅚ": "hl", "ㅝ": "nj", "ㅞ": "np", "ㅟ": "nl", "ㅢ": "ml",
    "ㄳ": "rt", "ㄵ": "sw", "ㄶ": "sg", "ㄺ": "fr", "ㄻ": "fa", "ㄼ": "fq",
    "ㄽ": "ft", "ㄾ": "fx", "ㄿ": "fv", "ㅀ": "fg", "ㅄ": "qt",
})

COMPOUND_JUNG = {
    ("ㅗ", "ㅏ"): "ㅘ", ("ㅗ", "ㅐ"): "ㅙ", ("ㅗ", "ㅣ"): "ㅚ",
    ("ㅜ", "ㅓ"): "ㅝ", ("ㅜ", "ㅔ"): "ㅞ", ("ㅜ", "ㅣ"): "ㅟ", ("ㅡ", "ㅣ"): "ㅢ",
}
COMPOUND_JONG = {
    ("ㄱ", "ㅅ"): "ㄳ", ("ㄴ", "ㅈ"): "ㄵ", ("ㄴ", "ㅎ"): "ㄶ", ("ㄹ", "ㄱ"): "ㄺ",
    ("ㄹ", "ㅁ"): "ㄻ", ("ㄹ", "ㅂ"): "ㄼ", ("ㄹ", "ㅅ"): "ㄽ", ("ㄹ", "ㅌ"): "ㄾ",
    ("ㄹ", "ㅍ"): "ㄿ", ("ㄹ", "ㅎ"): "ㅀ", ("ㅂ", "ㅅ"): "ㅄ",
}
SPLIT_JONG = {v: k for k, v in COMPOUND_JONG.items()}
JONG_OK = set(JONG)
CONSONANTS = set(CHO)

CHO_INDEX = {c: i for i, c in enumerate(CHO)}
JUNG_INDEX = {c: i for i, c in enumerate(JUNG)}
JONG_INDEX = {c: i + 1 for i, c in enumerate(JONG)}


def is_syllable(ch: str) -> bool:
    return "가" <= ch <= "힣"


def is_compat_jamo(ch: str) -> bool:
    return "ㄱ" <= ch <= "ㅣ"


def is_hangul(ch: str) -> bool:
    return is_syllable(ch) or is_compat_jamo(ch)


def to_keys(text: str) -> str:
    """한글 문자열을 두벌식 키 문자열로. 한글이 아닌 문자는 그대로 둔다."""
    out = []
    for ch in text:
        if is_syllable(ch):
            code = ord(ch) - 0xAC00
            cho, jung, jong = code // 588, (code % 588) // 28, code % 28
            out.append(JAMO_TO_KEYS[CHO[cho]])
            out.append(JAMO_TO_KEYS[JUNG[jung]])
            if jong:
                out.append(JAMO_TO_KEYS[JONG[jong - 1]])
        elif is_compat_jamo(ch):
            out.append(JAMO_TO_KEYS.get(ch, ch))
        else:
            out.append(ch)
    return "".join(out)


def jamo_of_key(ch: str):
    """키 → 자모. QWERTOP 밖의 대문자는 소문자 자모로 본다(Apple 두벌식과 같음)."""
    j = KEY_TO_JAMO.get(ch)
    if j is None and ch.isupper():
        j = KEY_TO_JAMO.get(ch.lower())
    return j


def compose(keys: str):
    """키 문자열을 두벌식 오토마타로 조립한다.

    반환: (한글 문자열, 단독 자모 수, Shift 위반 수)
    - 단독 자모: 모음 없는 자음 또는 자음 없는 모음으로 끝난 음절(ㅋㅋ, ㅠㅠ 포함).
    - Shift 위반: QWERTOP 밖의 대문자 키.
    """
    out = []
    cho = jung = jong = None
    lone = 0
    shift_bad = 0

    def flush():
        nonlocal cho, jung, jong, lone
        if cho is None and jung is None:
            return
        if cho is not None and jung is not None:
            code = 0xAC00 + CHO_INDEX[cho] * 588 + JUNG_INDEX[jung] * 28
            if jong is not None:
                code += JONG_INDEX[jong]
            out.append(chr(code))
        else:
            out.append(cho if cho is not None else jung)
            lone += 1
        cho = jung = jong = None

    for ch in keys:
        j = jamo_of_key(ch)
        if j is None:
            flush()
            out.append(ch)
            continue
        if ch.isupper() and ch not in SHIFT_KEYS:
            shift_bad += 1
        if j in CONSONANTS:
            if jung is None:
                if cho is not None:
                    flush()
                cho = j
            elif cho is None:
                flush()
                cho = j
            elif jong is None:
                if j in JONG_OK:
                    jong = j
                else:
                    flush()
                    cho = j
            else:
                comp = COMPOUND_JONG.get((jong, j))
                if comp:
                    jong = comp
                else:
                    flush()
                    cho = j
        else:
            if jung is None:
                jung = j
            elif jong is None:
                comp = COMPOUND_JUNG.get((jung, j))
                if comp:
                    jung = comp
                else:
                    flush()
                    jung = j
            else:
                if jong in SPLIT_JONG:
                    first, second = SPLIT_JONG[jong]
                    jong = first
                    flush()
                    cho, jung = second, j
                else:
                    moved = jong
                    jong = None
                    flush()
                    cho, jung = moved, j
    flush()
    return "".join(out), lone, shift_bad


if __name__ == "__main__":
    import sys
    for arg in sys.argv[1:]:
        text, lone, bad = compose(arg)
        print(f"{arg}\t{text}\tlone={lone}\tshift_bad={bad}\tback={to_keys(text)}")
