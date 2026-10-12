"""학습된 분류기를 Swift Engine이 읽는 JSON으로 내보낸다.

사용: python3 -I tools/export_model.py [--min-count 1] [--out models/hanyoung.json]
n-gram 카운트는 {context: {char: count}} 그대로 둔다. 가중치(실수)는 소수 3자리로 반올림.
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from classify import load, JAMO_LEXICON  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..")


def lm_json(lm, min_count):
    counts = {}
    for ctx, c in lm.counts.items():
        kept = {ch: (round(v, 3) if isinstance(v, float) else v) for ch, v in c.items() if v >= min_count}
        if kept:
            counts[ctx] = kept
    return {"order": lm.order, "vocab": "".join(sorted(lm.vocab)), "counts": counts}


def lex_json(lex, min_count):
    return {w: (round(v, 3) if isinstance(v, float) else v) for w, v in lex.items() if v >= min_count}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default=os.path.join(ROOT, "models", "hanyoung.pkl"))
    ap.add_argument("--out", default=os.path.join(ROOT, "models", "hanyoung.json"))
    ap.add_argument("--min-count", type=float, default=0)
    args = ap.parse_args()

    clf = load(args.model)
    p = clf.p
    doc = {
        "version": 1,
        "params": {
            "lone_penalty": p.lone_penalty, "shift_penalty": p.shift_penalty,
            "max_suffix": p.max_suffix, "min_prefix": p.min_prefix, "mix_penalty": p.mix_penalty,
            "lex_lambda_ko": p.lex_lambda_ko, "lex_lambda_en": p.lex_lambda_en,
            "suffix_lambda": p.suffix_lambda, "fold_weight": clf.en.fold_weight,
            "jamo_mass": p.jamo_mass, "run_attach_prob": p.run_attach_prob, "repeat_decay": p.repeat_decay,
            "jamo_lex": JAMO_LEXICON,
            "prior": p.prior,
        },
        "ko_lm": lm_json(clf.ko.lm, args.min_count),
        "en_lm": lm_json(clf.en.lm, args.min_count),
        # 접미 n-gram은 카운트로 내보내고 Swift가 로드할 때 만든다 (개인 층 접미를 더할 수 있게)
        "suffix_counts": lex_json(clf.suffix_counts, args.min_count),
        "ko_lex": lex_json(clf.ko.lex, args.min_count),
        "en_lex": lex_json(clf.en.lex, args.min_count),
        "ko_lex_total": clf.ko.total,
        "en_lex_total": clf.en.total,
    }
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, separators=(",", ":"))
    size = os.path.getsize(args.out) / 1e6
    print(f"{args.out}: {size:.1f} MB, ko ctx {len(doc['ko_lm']['counts'])}, en ctx {len(doc['en_lm']['counts'])}, "
          f"ko lex {len(doc['ko_lex'])}, en lex {len(doc['en_lex'])}")


if __name__ == "__main__":
    main()
