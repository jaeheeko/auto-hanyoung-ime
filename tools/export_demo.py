"""웹 데모용 JSON 모델을 만든다 → docs/model.json

사용: python3 -I tools/export_demo.py [--model models/hanyoung.pkl] [--ko 3] [--en-lm 3] [--en-lex 1] [--out docs/model.json]

GitHub Pages가 gzip으로 내보내므로 JSON이면 충분하다(수 MB → 2~3MB 전송). 포맷은 docs/hanyoung.js가 읽는다.
  { "params": {...}, "suffix": {keys: count},
    "ko": {"order", "vocab", "counts": {ctx: {ch: count}}, "lex": {keys: count}, "lam"},
    "en": {... , "fold_weight"} }
문맥·단어는 해시가 아니라 문자열 그대로다. BOS/EOS는 \\u0002 \\u0003.
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from classify import load, JAMO_LEXICON  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..")


def lm_dict(lm):
    return {"order": lm.order, "vocab": "".join(sorted(lm.vocab)),
            "counts": {ctx: dict(c) for ctx, c in lm.counts.items()}}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default=os.path.join(ROOT, "models", "hanyoung.pkl"))
    ap.add_argument("--prune", type=float, default=5,
                    help="전체(n-gram·사전·접미) 가지치기 최소 카운트. 5면 vault 테스트 99.80%%(원본 99.86%%), gzip 1.9MB")
    ap.add_argument("--ko", type=float, default=0, help="한국어만 따로 가지치기할 때")
    ap.add_argument("--en-lm", type=float, default=0)
    ap.add_argument("--en-lex", type=float, default=0)
    ap.add_argument("--out", default=os.path.join(ROOT, "docs", "model.json"))
    args = ap.parse_args()

    clf = load(args.model)
    if args.prune:
        clf.prune(args.prune)
    if args.ko:
        clf.ko.lm.prune(args.ko)
        clf.ko.prune(args.ko)
    if args.en_lm:
        clf.en.lm.prune(args.en_lm)
    if args.en_lex:
        clf.en.prune(args.en_lex)
    p = clf.p
    d = {
        "version": 1,
        "params": {
            "lone_penalty": p.lone_penalty, "shift_penalty": p.shift_penalty,
            "max_suffix": p.max_suffix, "min_prefix": p.min_prefix, "mix_penalty": p.mix_penalty,
            "suffix_lambda": p.suffix_lambda, "suffix_oov_penalty": p.suffix_oov_penalty,
            "jamo_mass": p.jamo_mass, "run_attach_prob": p.run_attach_prob, "repeat_decay": p.repeat_decay,
            "jamo_lex": JAMO_LEXICON, "prior": p.prior,
        },
        "suffix": dict(clf.suffix_counts),
        "ko": {**lm_dict(clf.ko.lm), "lex": dict(clf.ko.lex), "lam": clf.ko.lam},
        "en": {**lm_dict(clf.en.lm), "lex": dict(clf.en.lex), "lam": clf.en.lam, "fold_weight": clf.en.fold_weight},
    }
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, separators=(",", ":"))
    print(f"{args.out}: {os.path.getsize(args.out) / 1e6:.1f} MB, ko ctx {len(clf.ko.lm.counts)} lex {len(clf.ko.lex)}, "
          f"en ctx {len(clf.en.lm.counts)} lex {len(clf.en.lex)}, suffix {len(clf.suffix_counts)}")


if __name__ == "__main__":
    main()
