"""문서 폴더의 .md/.txt 파일에서 어절 토큰을 뽑아 train/test로 나눈다.

출력: data/train.tsv, data/test.tsv — 한 줄에 `file_id \t label \t token \t keys`.
파일 순서가 보존되고, 줄이 바뀌는 자리에는 label=BR 행이 들어간다(문맥 사전확률 평가용).
label: KO(한글만) / EN(영문자만) / MIX(영문 접두+한글 접미) / BR(줄 경계)
숫자·기호가 섞인 토큰은 규칙으로 처리할 대상이라 제외한다.

사용: python3 -I tools/corpus.py <문서 폴더> [--test-ratio 0.2]
한국어와 영어가 섞인 본인의 글(노트, 메시지 내보내기 등)이 가장 좋은 학습 데이터다.
"""
import argparse
import hashlib
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from hangul import to_keys  # noqa: E402

RE_FRONTMATTER = re.compile(r"\A---\n.*?\n---\n", re.S)
RE_FENCE = re.compile(r"```.*?```", re.S)
RE_INLINE_CODE = re.compile(r"`[^`\n]*`")
RE_URL = re.compile(r"https?://\S+|www\.\S+")
RE_WIKILINK = re.compile(r"\[\[([^\]|]*)(?:\|([^\]]*))?\]\]")
RE_MDLINK = re.compile(r"\[([^\]]*)\]\([^)]*\)")
RE_HTML = re.compile(r"<[^>\n]+>")
RE_TAG = re.compile(r"(?<!\S)#[\w가-힣/_-]+")

RE_KO = re.compile(r"^[가-힣ㄱ-ㅣ]+$")
RE_EN = re.compile(r"^[A-Za-z]+(?:['’][A-Za-z]+)?$")
RE_MIX = re.compile(r"^([A-Za-z]+(?:['’][A-Za-z]+)?)([가-힣]+)$")

STRIP_CHARS = "\"'“”‘’()[]{}<>,.!?;:…·~`*_|#-—–/\\+=^%$&@"


def clean(text: str) -> str:
    text = RE_FRONTMATTER.sub("", text)
    text = RE_FENCE.sub(" ", text)
    text = RE_INLINE_CODE.sub(" ", text)
    text = RE_URL.sub(" ", text)
    text = RE_WIKILINK.sub(lambda m: m.group(2) or m.group(1), text)
    text = RE_MDLINK.sub(r"\1", text)
    text = RE_HTML.sub(" ", text)
    text = RE_TAG.sub(" ", text)
    return text


def label_of(token: str):
    if RE_KO.match(token):
        return "KO"
    if RE_EN.match(token):
        return "EN"
    if RE_MIX.match(token):
        return "MIX"
    return None


def keys_of(token: str, label: str) -> str:
    if label == "KO":
        return to_keys(token)
    if label == "EN":
        return token.replace("’", "'")
    m = RE_MIX.match(token)
    return m.group(1).replace("’", "'") + to_keys(m.group(2))


def iter_tokens(text: str):
    """줄 단위로 토큰을 낸다. 줄 끝에는 ("BR", "", "")."""
    for line in clean(text).split("\n"):
        emitted = False
        for raw in line.split():
            token = raw.strip(STRIP_CHARS)
            if not token:
                continue
            label = label_of(token)
            if label is None:
                continue
            yield label, token, keys_of(token, label)
            emitted = True
        if emitted:
            yield "BR", "", ""


def md_files(root: str):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for name in filenames:
            if name.endswith((".md", ".txt")):
                yield os.path.join(dirpath, name)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("vault", metavar="FOLDER")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "data"))
    ap.add_argument("--test-ratio", type=float, default=0.2)
    ap.add_argument("--exclude", default="", help="파일 이름에 이 문자열(쉼표 구분)이 들어가면 제외")
    args = ap.parse_args()
    excludes = [e for e in args.exclude.split(",") if e]

    os.makedirs(args.out, exist_ok=True)
    counts = {"train": {}, "test": {}}
    with open(os.path.join(args.out, "train.tsv"), "w") as ftrain, \
            open(os.path.join(args.out, "test.tsv"), "w") as ftest:
        for i, path in enumerate(sorted(md_files(args.vault))):
            rel = os.path.relpath(path, args.vault)
            if any(e in os.path.basename(path) for e in excludes):
                continue
            h = int(hashlib.md5(rel.encode()).hexdigest(), 16) % 1000
            split = "test" if h < args.test_ratio * 1000 else "train"
            f = ftest if split == "test" else ftrain
            with open(path, encoding="utf-8", errors="ignore") as fh:
                text = fh.read()
            for label, token, keys in iter_tokens(text):
                f.write(f"{i}\t{label}\t{token}\t{keys}\n")
                counts[split][label] = counts[split].get(label, 0) + 1
    for split in ("train", "test"):
        c = counts[split]
        print(split, {k: c.get(k, 0) for k in ("KO", "EN", "MIX", "BR")})


if __name__ == "__main__":
    main()
