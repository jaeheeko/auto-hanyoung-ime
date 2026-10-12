"""문자 n-gram 언어모델 (Witten-Bell 보간) + 어휘 사전 혼합.

키 문자열 하나(어절)에 대해 log P(keys)를 돌려준다. BOS/EOS를 포함하므로
서로 다른 가설의 점수를 같은 키 문자열 위에서 직접 비교할 수 있다.
"""
import math
from collections import Counter, defaultdict

BOS = "\x02"
EOS = "\x03"


class CharLM:
    def __init__(self, order: int = 5):
        self.order = order
        # context(str) -> Counter(next char)
        self.counts = defaultdict(Counter)
        self.vocab = set()

    def train(self, words, weights=None):
        pad = BOS * (self.order - 1)
        for idx, w in enumerate(words):
            wt = 1 if weights is None else weights[idx]
            s = pad + w + EOS
            for i in range(self.order - 1, len(s)):
                ch = s[i]
                self.vocab.add(ch)
                for k in range(0, self.order):
                    ctx = s[i - k:i]
                    self.counts[ctx][ch] += wt
        self._finalize()

    def _finalize(self):
        self.totals = {ctx: sum(c.values()) for ctx, c in self.counts.items()}
        self.types = {ctx: len(c) for ctx, c in self.counts.items()}
        self.vsize = len(self.vocab) + 1

    def prob(self, ctx: str, ch: str) -> float:
        p = 1.0 / self.vsize
        # 짧은 문맥부터 보간해 올라간다
        for k in range(0, len(ctx) + 1):
            c = ctx[len(ctx) - k:] if k else ""
            counter = self.counts.get(c)
            if counter is None:
                break
            n = self.totals[c]
            t = self.types[c]
            p = (counter.get(ch, 0) + t * p) / (n + t)
        return p

    def logprob(self, word: str, eos: bool = True) -> float:
        """eos=False면 어절이 아직 끝나지 않은(조합 중) 접두로 본다."""
        s = BOS * (self.order - 1) + word + (EOS if eos else "")
        lp = 0.0
        for i in range(self.order - 1, len(s)):
            lp += math.log(self.prob(s[i - self.order + 1:i], s[i]))
        return lp

    def to_dict(self):
        return {
            "order": self.order,
            "vocab": "".join(sorted(self.vocab)),
            "counts": {ctx: dict(c) for ctx, c in self.counts.items()},
        }

    @classmethod
    def from_dict(cls, d):
        lm = cls(d["order"])
        lm.vocab = set(d["vocab"])
        for ctx, c in d["counts"].items():
            lm.counts[ctx] = Counter(c)
        lm._finalize()
        return lm


class WordModel:
    """어휘 사전(빈도)과 문자 n-gram을 혼합한 어절 확률.

    P(w) = lam * P_lex(w) + (1 - lam) * P_ngram(w)
    """

    def __init__(self, lm: CharLM, lexicon: Counter, lam: float = 0.5, case_fold: bool = False):
        self.lm = lm
        self.lex = lexicon
        self.total = sum(lexicon.values())
        self.lam = lam
        # 영어: `Then`, `API`처럼 대문자가 섞인 단어는 소문자형으로도 조회한다 (가중치 0.3)
        self.case_fold = case_fold
        self.fold_weight = 0.3

    def _prob(self, word: str, eos: bool) -> float:
        p_ng = math.exp(self.lm.logprob(word, eos))
        if not eos:
            # 접두 모드: 사전은 완성 어절만 알므로 n-gram만 쓴다
            return p_ng
        c = self.lex.get(word, 0)
        p_lex = c / self.total if self.total else 0.0
        return self.lam * p_lex + (1 - self.lam) * p_ng

    def logprob(self, word: str, eos: bool = True) -> float:
        p = self._prob(word, eos)
        if self.case_fold and word != word.lower() and any(ch.isupper() for ch in word):
            p = max(p, self.fold_weight * self._prob(word.lower(), eos))
        return math.log(p)

    def logprob_ngram(self, word: str, eos: bool = True) -> float:
        return self.lm.logprob(word, eos)
