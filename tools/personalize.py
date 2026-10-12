"""본인 문서로 개인 어휘 층(user_lexicon.json)을 만든다.

사용: python3 -I tools/personalize.py <문서 폴더> [--out PATH] [--min-count 1] [--exclude a,b]

입력기가 시작할 때 이 파일의 어절 빈도를 기본 모델의 어휘 사전에 더한다(n-gram은 그대로).
문서 내용은 저장되지 않고 어절(키열) 빈도만 남는다. 기본 출력 위치는
~/Library/Application Support/Hanyoung/user_lexicon.json 이며, 입력기를 다시 시작하면 반영된다.
"""
import argparse
import json
import os
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(__file__))
from classify import count_words  # noqa: E402
from corpus import iter_tokens, md_files  # noqa: E402

DEFAULT_OUT = os.path.expanduser("~/Library/Application Support/Hanyoung/user_lexicon.json")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("folder", help=".md/.txt가 들어 있는 폴더 (하위 폴더 포함)")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--min-count", type=int, default=1, help="이 횟수 미만으로 나온 어절은 버린다")
    ap.add_argument("--exclude", default="", help="파일 이름에 이 문자열(쉼표 구분)이 들어가면 제외")
    ap.add_argument("--dry-run", action="store_true", help="파일을 쓰지 않고 통계만 출력")
    args = ap.parse_args()
    excludes = [e for e in args.exclude.split(",") if e]

    rows = []
    files = 0
    for path in sorted(md_files(args.folder)):
        if any(e in os.path.basename(path) for e in excludes):
            continue
        files += 1
        with open(path, encoding="utf-8", errors="ignore") as fh:
            for label, token, keys in iter_tokens(fh.read()):
                rows.append((0, label, token, keys))
    ko, en, suffix = count_words(rows)

    def keep(counter):
        return {w: c for w, c in counter.items() if c >= args.min_count}

    doc = {
        "version": 1,
        "source": os.path.abspath(args.folder),
        "created": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "stats": {"files": files, "ko_tokens": sum(ko.values()), "en_tokens": sum(en.values()),
                  "mix_tokens": sum(suffix.values())},
        "ko": keep(ko), "en": keep(en), "suffix": keep(suffix),
    }
    print(f"파일 {files}개, 어절 KO {sum(ko.values())} / EN {sum(en.values())} / MIX {sum(suffix.values())}, "
          f"사전 항목 KO {len(doc['ko'])} / EN {len(doc['en'])} / 접미 {len(doc['suffix'])}")
    if args.dry_run:
        return
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, separators=(",", ":"))
    print(f"저장: {args.out} ({os.path.getsize(args.out) / 1e6:.1f} MB). 입력기를 다시 시작하면 반영된다.")


if __name__ == "__main__":
    main()
