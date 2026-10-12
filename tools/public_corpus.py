"""data/public/raw/ 의 공개 코퍼스를 한 줄에 한 문장인 평문(.txt)으로 바꾼다.

출력: data/public/text/<이름>.txt — 이후 corpus.py가 이 폴더를 읽는다.
사용: python3 -I tools/public_corpus.py
"""
import csv
import json
import os
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..")
RAW = os.path.join(ROOT, "data", "public", "raw")
OUT = os.path.join(ROOT, "data", "public", "text")

csv.field_size_limit(1 << 24)


def write(name, lines):
    seen = set()
    n = 0
    with open(os.path.join(OUT, name + ".txt"), "w", encoding="utf-8") as f:
        for line in lines:
            line = " ".join(line.split())
            if not line or line in seen:
                continue
            seen.add(line)
            f.write(line + "\n")
            n += 1
    print(f"{name}: {n} lines")


def nsmc():
    path = os.path.join(RAW, "nsmc_ratings.txt")
    if not os.path.exists(path):
        return
    with open(path, encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE)
        write("nsmc", (row["document"] for row in reader))


def kornli(name):
    path = os.path.join(RAW, f"kornli_{name}.tsv")
    if not os.path.exists(path):
        return

    def lines():
        with open(path, encoding="utf-8") as f:
            reader = csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE)
            for row in reader:
                yield row.get("sentence1", "")
                yield row.get("sentence2", "")
    write(f"kornli_{name}", lines())


def korquad():
    path = os.path.join(RAW, "korquad_v1_train.json")
    if not os.path.exists(path):
        return
    with open(path, encoding="utf-8") as f:
        data = json.load(f)

    def lines():
        for article in data["data"]:
            for para in article["paragraphs"]:
                yield para["context"]
                for qa in para["qas"]:
                    yield qa["question"]
    write("korquad", lines())


def ynat():
    path = os.path.join(RAW, "klue_ynat_train.json")
    if not os.path.exists(path):
        return
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    write("klue_ynat", (item["title"] for item in data))


def main():
    os.makedirs(OUT, exist_ok=True)
    nsmc()
    kornli("multinli")
    kornli("snli")
    korquad()
    ynat()


if __name__ == "__main__":
    main()
