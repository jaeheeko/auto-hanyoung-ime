"""어절 키 문자열에 대한 KO / EN / MIX 가설 판정.

score(h) = log P(keys | h) + log P(h | 문맥)
"""
import math
import os
import pickle
import sys
from collections import Counter
from dataclasses import dataclass, field

sys.path.insert(0, os.path.dirname(__file__))
from hangul import compose, to_keys, is_hangul, is_compat_jamo, jamo_of_key, SHIFT_KEYS, CONSONANTS  # noqa: E402
from lm import CharLM, WordModel  # noqa: E402

LABELS = ("KO", "EN", "MIX")

# 자모 관용 표현. vault(노트)에는 거의 없어 손으로 심는다. 키열 → 상대 빈도.
# 반복은 2개로 접어서 조회하므로 ㅋㅋㅋㅋ도 "zz"에 해당한다.
JAMO_LEXICON = {
    "zz": 35, "gg": 15, "bb": 12, "nn": 4,                       # ㅋㅋ ㅎㅎ ㅠㅠ ㅜㅜ
    "g": 2,                                                      # ㅎ (ㅋ·ㅠ 한 글자는 영어 z·b와 충돌해 제외)
    "dd": 3, "dz": 3, "rr": 4, "ss": 2, "ee": 3,                 # ㅇㅇ ㅇㅋ ㄱㄱ ㄴㄴ ㄷㄷ
    "wt": 2, "tr": 2, "rt": 2, "fd": 2, "qq": 1, "ac": 1,        # ㅈㅅ ㅅㄱ ㄱㅅ ㄹㅇ ㅂㅂ ㅁㅊ
    "cz": 1, "gd": 1, "qd": 0.5, "dw": 1, "Rq": 0.5, "hni": 0.5, # ㅊㅋ ㅎㅇ ㅂㅇ ㅇㅈ ㄲㅂ ㅗㅜㅑ
}
JAMO_TOTAL = sum(JAMO_LEXICON.values())
# 음절 뒤·앞에 반복돼 붙는 자모 (ㅋ ㅎ ㅠ ㅜ). ㅡ(m)는 "10mm" 같은 단위와 충돌해 제외.
EMOTICON_RUN_KEYS = set("zgbn")


def collapse_runs(keys: str):
    """같은 키의 3회 이상 반복을 2회로 접는다. (접은 키열, 제거한 글자 수)"""
    out = []
    extra = 0
    for ch in keys:
        if len(out) >= 2 and out[-1] == ch and out[-2] == ch:
            extra += 1
        else:
            out.append(ch)
    return "".join(out), extra


def strip_runs(keys: str):
    """EMOTICON_RUN_KEYS의 2회 이상 반복을 떼어 낸다. (나머지, [run 길이...], 끝이 run인지)"""
    rest = []
    runs = []
    ends_with_run = False
    i, n = 0, len(keys)
    while i < n:
        j = i
        while j < n and keys[j] == keys[i]:
            j += 1
        if keys[i] in EMOTICON_RUN_KEYS and j - i >= 2:
            runs.append(j - i)
            ends_with_run = j == n
        else:
            rest.append(keys[i:j])
            ends_with_run = False
        i = j
    return "".join(rest), runs, ends_with_run


@dataclass
class Params:
    lone_penalty: float = 4.0        # 단독 자모 1개당 벌점 (log)
    shift_penalty: float = 6.0       # QWERTOP 밖 대문자 1개당 벌점 (KO 가설)
    max_suffix: int = 24             # MIX 접미 최대 키 수
    min_prefix: int = 1
    mix_penalty: float = 3.0         # MIX 가설 분할 벌점 (log). 짧은 우연 접두(sha과) 억제
    lex_lambda_ko: float = 0.5
    lex_lambda_en: float = 0.5
    suffix_lambda: float = 0.7       # 접미 n-gram 비중, 나머지는 일반 KO n-gram
    dict_weight: float = 0.2         # /usr/share/dict/words 단어 1개의 학습 가중치
    jamo_mass: float = 0.01          # 전체 어절 중 자모 관용 표현(ㅋㅋ 등)의 비중
    run_attach_prob: float = 0.02    # 음절에 반복 자모(굿ㅋㅋ)가 붙을 확률
    repeat_decay: float = 0.3        # 반복 자모 3개째부터 글자당 비용 (log)
    # 사전확률: 직전 언어별 다음 언어 분포 (log). 학습 데이터에서 추정.
    prior: dict = field(default_factory=dict)


@dataclass
class Decision:
    label: str
    text: str            # 선택된 가설로 렌더링한 문자열
    split: int           # MIX일 때 분할 위치, 아니면 -1
    scores: dict         # label -> 최고 점수
    margin: float        # 1위 - 2위


class Classifier:
    def __init__(self, ko: WordModel, en: WordModel, suffix_lm: CharLM, params: Params):
        self.ko = ko
        self.en = en
        self.suffix_lm = suffix_lm
        self.p = params

    # --- 가설별 log P(keys | h). final=False는 조합 중(접두) 점수 ---
    @staticmethod
    def _canon(keys: str) -> str:
        """KO 가설용 키열: QWERTOP 밖의 대문자는 소문자로."""
        return "".join(c if (c in SHIFT_KEYS or not c.isupper()) else c.lower() for c in keys)

    @staticmethod
    def _trailing_lone_cho(keys: str, text: str) -> bool:
        return bool(keys) and jamo_of_key(keys[-1]) in CONSONANTS and bool(text) and is_compat_jamo(text[-1])

    def _ko_word_loglik(self, keys: str, eos: bool):
        """키열을 한국어 어절 하나로 보고 매긴 점수. (점수, 조립 문자열)"""
        text, lone, shift_bad = compose(keys)
        if not eos and self._trailing_lone_cho(keys, text):
            lone -= 1  # 조합 중 말미의 초성은 정상
        lp = self.ko.logprob(self._canon(keys), eos=eos)
        lp -= self.p.lone_penalty * lone + self.p.shift_penalty * shift_bad
        return lp, text

    def emoticon_loglik(self, keys: str, final: bool):
        """자모 관용 표현(ㅋㅋ, 굿ㅠㅠ) 경로. 해당 없으면 None."""
        p = self.p
        collapsed, extra = collapse_runs(keys)
        w = JAMO_LEXICON.get(collapsed)
        if w is not None:
            return math.log(p.jamo_mass * w / JAMO_TOTAL) - p.repeat_decay * extra
        rest, runs, ends_with_run = strip_runs(keys)
        if not runs:
            return None
        run_cost = sum(math.log(p.run_attach_prob) - p.repeat_decay * (n - 2) for n in runs)
        if not rest:
            return math.log(p.jamo_mass) + run_cost
        # 반복 자모가 끝에 있으면 앞의 어절은 완성된 것으로 본다
        lp, _ = self._ko_word_loglik(rest, eos=final or ends_with_run)
        return lp + run_cost

    def ko_loglik(self, keys: str, final: bool = True):
        lp, text = self._ko_word_loglik(keys, eos=final)
        alt = self.emoticon_loglik(keys, final)
        if alt is not None and alt > lp:
            lp = alt
        return lp, text

    def en_loglik(self, keys: str, final: bool = True):
        return self.en.logprob(keys, eos=final), keys

    def suffix_loglik(self, suffix: str, final: bool = True):
        text, lone, shift_bad = compose(suffix)
        if not final and self._trailing_lone_cho(suffix, text):
            lone -= 1
        if lone or shift_bad:
            return -math.inf, text
        p_suf = math.exp(self.suffix_lm.logprob(suffix, eos=final))
        p_ng = math.exp(self.ko.logprob_ngram(suffix, eos=final))
        return math.log(self.p.suffix_lambda * p_suf + (1 - self.p.suffix_lambda) * p_ng), text

    def mix_loglik(self, keys: str, final: bool = True):
        best = (-math.inf, "", -1)
        n = len(keys)
        for i in range(max(self.p.min_prefix, n - self.p.max_suffix), n):
            prefix, suffix = keys[:i], keys[i:]
            if not prefix.replace("'", "").isalpha():
                continue
            s_lp, s_text = self.suffix_loglik(suffix, final)
            if s_lp == -math.inf:
                continue
            # 영어 접두는 완성된 단어이므로 항상 EOS 포함
            lp = self.en.logprob(prefix) + s_lp - self.p.mix_penalty
            if lp > best[0]:
                best = (lp, prefix + s_text, i)
        return best

    def decide(self, keys: str, prev: str = "BR", app_bias: dict = None, final: bool = True) -> Decision:
        prior = self.p.prior.get(prev) or self.p.prior.get("BR") or {}
        ko_lp, ko_text = self.ko_loglik(keys, final)
        en_lp, en_text = self.en_loglik(keys, final)
        mix_lp, mix_text, split = self.mix_loglik(keys, final)
        scores = {
            "KO": ko_lp + prior.get("KO", 0.0),
            "EN": en_lp + prior.get("EN", 0.0),
            "MIX": mix_lp + prior.get("MIX", 0.0),
        }
        if app_bias:
            for k, v in app_bias.items():
                scores[k] += v
        ranked = sorted(scores.items(), key=lambda kv: -kv[1])
        label = ranked[0][0]
        text = {"KO": ko_text, "EN": en_text, "MIX": mix_text}[label]
        margin = ranked[0][1] - ranked[1][1]
        return Decision(label, text, split if label == "MIX" else -1, scores, margin)


# --- 학습 ---

def read_tsv(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) == 4:
                rows.append(tuple(parts))
    return rows


def estimate_prior(rows):
    """직전 라벨 -> 다음 라벨 분포 (log). BR은 줄 처음."""
    trans = {}
    prev = "BR"
    for _, label, _, _ in rows:
        if label == "BR":
            prev = "BR"
            continue
        trans.setdefault(prev, Counter())[label] += 1
        prev = label
    prior = {}
    for p, c in trans.items():
        total = sum(c.values()) + len(LABELS)
        prior[p] = {l: math.log((c.get(l, 0) + 1) / total) for l in LABELS}
    return prior


def load_en_frequency(path):
    """hermitdave FrequencyWords 형식: `word count`."""
    lex = Counter()
    if not os.path.exists(path):
        return lex
    with open(path, encoding="utf-8") as f:
        for line in f:
            parts = line.split()
            if len(parts) == 2 and parts[0].isalpha():
                lex[parts[0]] += int(parts[1])
    return lex


def load_dict_words(path="/usr/share/dict/words"):
    words = []
    if not os.path.exists(path):
        return words
    with open(path, encoding="utf-8", errors="ignore") as f:
        for line in f:
            w = line.strip()
            if 2 <= len(w) <= 20 and w.isalpha():
                words.append(w)
    return words


def train(train_rows, external_dir, order=5, params: Params = None):
    params = params or Params()
    ko_words, en_words, suffixes = Counter(), Counter(), Counter()
    for _, label, token, keys in train_rows:
        if label == "KO":
            ko_words[keys] += 1
        elif label == "EN":
            en_words[keys] += 1
        elif label == "MIX":
            # 접두 영어는 영어 어휘로, 접미는 접미 사전으로. 분할점은 토큰의 한글 꼬리로 역산.
            prefix_len = len(keys) - len(_ko_tail_keys(token))
            en_words[keys[:prefix_len]] += 1
            suffixes[keys[prefix_len:]] += 1

    ko_lm = CharLM(order)
    ko_lm.train(list(ko_words.elements()))

    # 영어: vault 영어 토큰(가중치 1) + 빈도표(스케일 조정) + 사전 단어(1회)
    en_freq = load_en_frequency(os.path.join(external_dir, "en_50k.txt"))
    en_lex = Counter(en_words)
    if en_freq:
        scale = sum(en_words.values()) * 3 / sum(en_freq.values())
        for w, c in en_freq.items():
            en_lex[w] += max(1, int(c * scale))
    for w in load_dict_words():
        en_lex[w] += params.dict_weight
    en_lm = CharLM(order)
    en_lm.train(list(en_lex.keys()), weights=list(en_lex.values()))

    suffix_lm = CharLM(order)
    suffix_lm.train(list(suffixes.keys()), weights=list(suffixes.values()))

    params.prior = estimate_prior(train_rows)
    ko_model = WordModel(ko_lm, ko_words, params.lex_lambda_ko)
    en_model = WordModel(en_lm, en_lex, params.lex_lambda_en, case_fold=True)
    return Classifier(ko_model, en_model, suffix_lm, params)


def _ko_tail_keys(token: str) -> str:
    i = len(token)
    while i > 0 and is_hangul(token[i - 1]):
        i -= 1
    return to_keys(token[i:])


def save(clf: Classifier, path: str):
    with open(path, "wb") as f:
        pickle.dump({
            "ko_lm": clf.ko.lm.to_dict(), "ko_lex": clf.ko.lex,
            "en_lm": clf.en.lm.to_dict(), "en_lex": clf.en.lex,
            "suffix_lm": clf.suffix_lm.to_dict(), "params": clf.p,
        }, f)


def load(path: str) -> Classifier:
    with open(path, "rb") as f:
        d = pickle.load(f)
    p = d["params"]
    ko = WordModel(CharLM.from_dict(d["ko_lm"]), d["ko_lex"], p.lex_lambda_ko)
    en = WordModel(CharLM.from_dict(d["en_lm"]), d["en_lex"], p.lex_lambda_en, case_fold=True)
    return Classifier(ko, en, CharLM.from_dict(d["suffix_lm"]), p)


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default=os.path.join(os.path.dirname(__file__), "..", "models", "hanyoung.pkl"))
    ap.add_argument("--prev", default="BR")
    ap.add_argument("keys", nargs="+")
    args = ap.parse_args()
    clf = load(args.model)
    for k in args.keys:
        d = clf.decide(k, prev=args.prev)
        s = " ".join(f"{l}={v:.1f}" for l, v in d.scores.items())
        print(f"{k}\t{d.label}\t{d.text}\tmargin={d.margin:.1f}\t{s}")
