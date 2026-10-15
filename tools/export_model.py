"""학습된 분류기를 Swift Engine이 읽는 바이너리(.model)로 내보낸다.

사용: python3 -I tools/export_model.py [--model models/hanyoung.pkl] [--out models/hanyoung.model] [--json 경로]

포맷 (리틀 엔디언):
  "HYM1" | header_len u32 | header JSON (params·prior·자모 사전·접미 카운트·fold_weight)
  이어서 섹션 4개: ko_lm, en_lm (n-gram), ko_lex, en_lex (어휘 사전). 각 섹션은 8바이트 정렬.
  n-gram: order u32, vsize u32, n_ctx u32, n_fol u32, pad u32 ×?, ctx_keys u64[n_ctx], ctx_totals f64[n_ctx],
          ctx_types u32[n_ctx], fol_keys u64[n_fol], fol_vals f32[n_fol]
  사전:   n u32, pad, total f64, keys u64[n], vals f32[n]
키는 문자열 대신 FNV-1a 64비트 해시다. 문맥 키 = fnv(ctx), 다음 문자 키 = fnv(ctx + "\\0" + ch), 단어 키 = fnv(word).
정렬된 배열 + 이진 탐색이라 Swift 쪽 메모리가 딕셔너리보다 훨씬 작다.
"""
import argparse
import json
import os
import struct
import sys
from array import array

sys.path.insert(0, os.path.dirname(__file__))
from classify import load, JAMO_LEXICON  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..")
MAGIC = b"HYM1"
FNV_OFFSET = 0xCBF29CE484222325
FNV_PRIME = 0x100000001B3
MASK = (1 << 64) - 1


def fnv1a(data: bytes) -> int:
    h = FNV_OFFSET
    for b in data:
        h = ((h ^ b) * FNV_PRIME) & MASK
    return h


def sorted_table(pairs, what):
    """[(hash, value...)] → 해시로 정렬. 충돌이 있으면 중단한다(2^64 공간이라 사실상 없음)."""
    pairs.sort(key=lambda p: p[0])
    for a, b in zip(pairs, pairs[1:]):
        if a[0] == b[0]:
            raise SystemExit(f"{what}: 해시 충돌 {a[0]:x}")
    return pairs


def pad8(f):
    rem = f.tell() % 8
    if rem:
        f.write(b"\0" * (8 - rem))


def write_array(f, typecode, values):
    a = array(typecode, values)
    assert sys.byteorder == "little"
    f.write(a.tobytes())


def write_lm(f, lm):
    ctx_pairs = [(fnv1a(ctx.encode()), lm.totals[ctx], lm.types[ctx]) for ctx in lm.counts]
    fol_pairs = []
    for ctx, counter in lm.counts.items():
        base = ctx.encode() + b"\0"
        for ch, v in counter.items():
            fol_pairs.append((fnv1a(base + ch.encode()), float(v)))
    sorted_table(ctx_pairs, "ctx")
    sorted_table(fol_pairs, "followers")
    pad8(f)
    f.write(struct.pack("<IIII", lm.order, lm.vsize, len(ctx_pairs), len(fol_pairs)))
    write_array(f, "Q", [p[0] for p in ctx_pairs])
    write_array(f, "d", [p[1] for p in ctx_pairs])
    write_array(f, "I", [p[2] for p in ctx_pairs])
    pad8(f)
    write_array(f, "Q", [p[0] for p in fol_pairs])
    write_array(f, "f", [p[1] for p in fol_pairs])
    return len(ctx_pairs), len(fol_pairs)


def write_lex(f, lex, total):
    pairs = sorted_table([(fnv1a(w.encode()), float(c)) for w, c in lex.items()], "lexicon")
    pad8(f)
    f.write(struct.pack("<IId", len(pairs), 0, float(total)))
    write_array(f, "Q", [p[0] for p in pairs])
    write_array(f, "f", [p[1] for p in pairs])
    return len(pairs)


def header_dict(clf):
    p = clf.p
    return {
        "version": 2,
        "params": {
            "lone_penalty": p.lone_penalty, "shift_penalty": p.shift_penalty,
            "max_suffix": p.max_suffix, "min_prefix": p.min_prefix, "mix_penalty": p.mix_penalty,
            "lex_lambda_ko": p.lex_lambda_ko, "lex_lambda_en": p.lex_lambda_en,
            "suffix_lambda": p.suffix_lambda, "suffix_oov_penalty": getattr(p, "suffix_oov_penalty", 8.0),
            "fold_weight": clf.en.fold_weight,
            "jamo_mass": p.jamo_mass, "run_attach_prob": p.run_attach_prob, "repeat_decay": p.repeat_decay,
            "jamo_lex": JAMO_LEXICON,
            "prior": p.prior,
        },
        "suffix_counts": dict(clf.suffix_counts),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default=os.path.join(ROOT, "models", "hanyoung.pkl"))
    ap.add_argument("--out", default=os.path.join(ROOT, "models", "hanyoung.model"))
    ap.add_argument("--json", help="디버그용으로 n-gram·사전을 JSON으로도 쓴다")
    args = ap.parse_args()

    clf = load(args.model)
    header = json.dumps(header_dict(clf), ensure_ascii=False, separators=(",", ":")).encode()
    with open(args.out, "wb") as f:
        f.write(MAGIC)
        f.write(struct.pack("<I", len(header)))
        f.write(header)
        ko = write_lm(f, clf.ko.lm)
        en = write_lm(f, clf.en.lm)
        kol = write_lex(f, clf.ko.lex, clf.ko.total)
        enl = write_lex(f, clf.en.lex, clf.en.total)
    print(f"{args.out}: {os.path.getsize(args.out) / 1e6:.1f} MB, ko n-gram ctx {ko[0]} fol {ko[1]}, "
          f"en n-gram ctx {en[0]} fol {en[1]}, ko lex {kol}, en lex {enl}")

    if args.json:
        doc = header_dict(clf)
        doc.update({
            "ko_lm": clf.ko.lm.to_dict(), "en_lm": clf.en.lm.to_dict(),
            "ko_lex": dict(clf.ko.lex), "en_lex": dict(clf.en.lex),
            "ko_lex_total": clf.ko.total, "en_lex_total": clf.en.total,
        })
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(doc, f, ensure_ascii=False, separators=(",", ":"))
        print(f"{args.json}: {os.path.getsize(args.json) / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
