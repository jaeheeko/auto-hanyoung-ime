"""학습 + 테스트 분할 평가.

사용: python3 -I tools/evaluate.py [--order 5] [--context gold|pred|none]
출력: 정확도, 혼동행렬, 오분류 상위 목록(data/errors.tsv), 접두 안정성.
"""
import argparse
import os
import sys
import time
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(__file__))
from classify import Params, read_tsv, train, save  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..")


def evaluate(clf, rows, context="pred", prefix_eval=True):
    conf = Counter()
    errors = Counter()
    error_examples = {}
    prev = "BR"
    n = 0
    correct = 0
    # 접두 안정성: 길이 k 접두에서의 판정이 최종 정답과 같은 비율
    prefix_hit = defaultdict(int)
    prefix_cnt = defaultdict(int)
    t0 = time.time()
    for _, label, token, keys in rows:
        if label == "BR":
            prev = "BR"
            continue
        ctx = prev if context != "none" else "BR"
        d = clf.decide(keys, prev=ctx)
        ok = d.label == label and (label != "MIX" or d.text == token)
        if label == "MIX" and d.label == "MIX" and d.text != token:
            conf[(label, "MIX*")] += 1
        else:
            conf[(label, d.label)] += 1
        n += 1
        correct += ok
        if not ok:
            key = (label, keys)
            errors[key] += 1
            error_examples[key] = (token, d.label, d.text, d.margin)
        if prefix_eval and len(keys) >= 3:
            for k in (1, 2, 3, 4):
                if k >= len(keys):
                    break
                pd = clf.decide(keys[:k], prev=ctx, final=False)
                # MIX의 접두는 영어이므로 접두 판정은 EN이면 맞다고 본다
                target = "EN" if label == "MIX" and k <= len(keys) - 1 else label
                prefix_cnt[k] += 1
                prefix_hit[k] += pd.label == target
        prev = label if context == "gold" else d.label
    elapsed = time.time() - t0
    return {
        "n": n, "acc": correct / n, "conf": conf, "errors": errors,
        "examples": error_examples, "elapsed": elapsed,
        "prefix": {k: prefix_hit[k] / prefix_cnt[k] for k in sorted(prefix_cnt)},
    }


def print_report(res):
    print(f"어절 {res['n']}개, 정확도 {res['acc'] * 100:.3f}%, {res['elapsed']:.1f}s")
    labels = ["KO", "EN", "MIX", "MIX*"]
    print("정답\\판정", *[f"{l:>7}" for l in labels])
    for g in ("KO", "EN", "MIX"):
        row = [res["conf"].get((g, p), 0) for p in labels]
        total = sum(row)
        acc = (res["conf"].get((g, g), 0) / total * 100) if total else 0
        print(f"{g:>9}", *[f"{v:7d}" for v in row], f"  recall {acc:.2f}%")
    print("접두 안정성(접두 길이 k에서 최종 라벨과 일치):",
          " ".join(f"k={k}:{v * 100:.1f}%" for k, v in res["prefix"].items()))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--order", type=int, default=5)
    ap.add_argument("--context", choices=["gold", "pred", "none"], default="pred")
    ap.add_argument("--lone", type=float, default=4.0)
    ap.add_argument("--mix-penalty", type=float, default=3.0)
    ap.add_argument("--train", default=os.path.join(ROOT, "data", "train.tsv"), help="학습 TSV (corpus.py 출력)")
    ap.add_argument("--test", default=os.path.join(ROOT, "data", "test.tsv"))
    ap.add_argument("--prior", choices=["estimate", "default"], default="estimate",
                    help="estimate: --prior-from(없으면 --train)에서 전이 확률 추정, default: 내장 기본값")
    ap.add_argument("--prior-from", help="사전확률을 추정할 TSV (예: 본인 문서의 train.tsv)")
    ap.add_argument("--lex-from", help="n-gram은 그대로 두고 어휘 사전에만 더할 TSV (개인 층 실험)")
    ap.add_argument("--no-prefix", action="store_true")
    ap.add_argument("--save", action="store_true")
    args = ap.parse_args()

    train_rows = read_tsv(args.train)
    test_rows = read_tsv(args.test)
    prior_rows = read_tsv(args.prior_from) if args.prior_from else None
    lex_rows = read_tsv(args.lex_from) if args.lex_from else None
    t0 = time.time()
    clf = train(train_rows, os.path.join(ROOT, "data", "external"), order=args.order,
                params=Params(lone_penalty=args.lone, mix_penalty=args.mix_penalty),
                prior=args.prior, prior_rows=prior_rows, lex_rows=lex_rows)
    print(f"학습 데이터 {args.train}: KO {sum(1 for r in train_rows if r[1] == 'KO')}, "
          f"EN {sum(1 for r in train_rows if r[1] == 'EN')}, MIX {sum(1 for r in train_rows if r[1] == 'MIX')}")
    print(f"학습 {time.time() - t0:.1f}s, KO 어휘 {len(clf.ko.lex)}, EN 어휘 {len(clf.en.lex)}")
    print("사전확률(log):", {k: {l: round(v, 2) for l, v in d.items()} for k, d in clf.p.prior.items()})

    res = evaluate(clf, test_rows, context=args.context, prefix_eval=not args.no_prefix)
    print_report(res)

    err_path = os.path.join(ROOT, "data", "errors.tsv")
    with open(err_path, "w") as f:
        f.write("count\tgold\ttoken\tkeys\tpred\tpred_text\tmargin\n")
        for (label, keys), c in res["errors"].most_common():
            token, plabel, ptext, margin = res["examples"][(label, keys)]
            f.write(f"{c}\t{label}\t{token}\t{keys}\t{plabel}\t{ptext}\t{margin:.1f}\n")
    print(f"오분류 유형 {len(res['errors'])}개 → {err_path}")
    print("상위 오분류:")
    for (label, keys), c in res["errors"].most_common(25):
        token, plabel, ptext, margin = res["examples"][(label, keys)]
        print(f"  {c:4d}  {label:3} {token!r:>18} keys={keys!r:<14} → {plabel:3} {ptext!r}  margin={margin:.1f}")

    if args.save:
        os.makedirs(os.path.join(ROOT, "models"), exist_ok=True)
        save(clf, os.path.join(ROOT, "models", "hanyoung.pkl"))
        print("저장: models/hanyoung.pkl")


if __name__ == "__main__":
    main()
