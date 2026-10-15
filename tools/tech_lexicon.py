"""기술 어휘 목록을 만든다 → data/external/tech_words.txt (`word weight` 형식, en_50k와 같은 꼴).

출처
  1. Stack Overflow 태그 (StackExchange API, CC BY-SA 4.0). 인기순 상위 N페이지(100개/페이지).
     앱 키 없이는 25페이지(2,500개)까지만 준다. 그 아래 태그는 질문 수천 개 미만이라 여기까지로 충분하다.
     태그는 `ruby-on-rails`, `node.js`처럼 붙어 있어 영문자 덩어리로 쪼갠다.
  2. GitHub Linguist languages.yml (MIT): 언어 이름·별칭·확장자.

사용: python3 -I tools/tech_lexicon.py [--pages 80] [--weight 5] [--cap 50] [--out data/external/tech_words.txt]
자막 빈도표에 없는 html, sql, http, sdk 같은 약어가 영어로 판정되게 하는 것이 목적이다.
단어 하나의 가중치는 자막 빈도표의 흔한 단어보다 훨씬 작게 두어 일반 영어 분포를 흔들지 않는다.
"""
import argparse
import gzip
import io
import json
import os
import re
import sys
import time
import urllib.request
from collections import Counter

ROOT = os.path.join(os.path.dirname(__file__), "..")
SO_URL = ("https://api.stackexchange.com/2.3/tags?order=desc&sort=popular&site=stackoverflow"
          "&pagesize=100&page={page}")
LINGUIST_URL = "https://raw.githubusercontent.com/github-linguist/linguist/main/lib/linguist/languages.yml"
WORD = re.compile(r"[A-Za-z]+")


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"Accept-Encoding": "gzip", "User-Agent": "hanyoung-tech-lexicon"})
    with urllib.request.urlopen(req, timeout=60) as r:
        raw = r.read()
        if r.headers.get("Content-Encoding") == "gzip" or raw[:2] == b"\x1f\x8b":
            raw = gzip.GzipFile(fileobj=io.BytesIO(raw)).read()
        return raw


def so_tags(pages: int):
    for page in range(1, min(pages, 25) + 1):
        try:
            d = json.loads(fetch(SO_URL.format(page=page)))
        except urllib.error.HTTPError as e:
            print(f"페이지 {page}: {e} — 여기까지 쓴다", file=sys.stderr)
            break
        for t in d.get("items", []):
            yield t["name"], int(t.get("count", 0))
        if d.get("backoff"):
            time.sleep(int(d["backoff"]) + 1)
        if not d.get("has_more"):
            break
        if d.get("quota_remaining", 1) <= 1:
            print("API 할당량 소진, 여기까지", file=sys.stderr)
            break


def linguist_words():
    """YAML을 간단히 읽는다: 최상위 키 = 언어 이름, `extensions:`/`aliases:` 아래 `- ...` 항목."""
    text = fetch(LINGUIST_URL).decode("utf-8")
    words = []
    section = None
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        s = line.strip()
        if indent == 0 and s.endswith(":"):
            words.append(s[:-1].strip('"'))
            section = None
        elif indent == 2 and s.endswith(":"):
            section = s[:-1]
        elif indent >= 2 and s.startswith("- ") and section in ("extensions", "aliases", "interpreters"):
            words.append(s[2:].strip('"'))
    return words


def tokens(name: str):
    for w in WORD.findall(name):
        if 2 <= len(w) <= 20:
            yield w


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pages", type=int, default=25, help="Stack Overflow 태그 페이지 수 (100개/페이지)")
    ap.add_argument("--weight", type=float, default=5.0, help="태그·언어 항목 하나당 토큰 가중치")
    ap.add_argument("--cap", type=float, default=50.0, help="토큰 하나의 가중치 상한")
    ap.add_argument("--out", default=os.path.join(ROOT, "data", "external", "tech_words.txt"))
    args = ap.parse_args()

    lex = Counter()
    n_tags = 0
    for name, _count in so_tags(args.pages):
        n_tags += 1
        for w in tokens(name):
            lex[w] += args.weight
    print(f"Stack Overflow 태그 {n_tags}개", file=sys.stderr)
    n_ling = 0
    for name in linguist_words():
        n_ling += 1
        for w in tokens(name):
            lex[w] += args.weight
    print(f"Linguist 항목 {n_ling}개", file=sys.stderr)

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        for w, c in sorted(lex.items(), key=lambda x: (-x[1], x[0])):
            f.write(f"{w} {min(c, args.cap):g}\n")
    print(f"{args.out}: 단어 {len(lex)}개, 총 가중치 {sum(min(c, args.cap) for c in lex.values()):g}", file=sys.stderr)


if __name__ == "__main__":
    main()
