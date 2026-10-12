#!/bin/bash
# 기본 모델 학습용 공개 한국어 코퍼스를 data/public/raw/ 에 내려받는다.
# 각 데이터의 라이선스는 아래와 같다. 모델 배포 전에 다시 확인한다.
# - NSMC (e9t/nsmc): 네이버 영화 리뷰 20만 건, CC0 1.0
# - KorNLI (kakaobrain/kor-nlu-datasets): 번역된 NLI 문장 쌍, CC BY-SA 4.0
# - KorQuAD 1.0 (korquad.github.io): 위키백과 문단 + 질문, CC BY-ND 2.0 KR
# - KLUE YNAT (KLUE-benchmark/KLUE): 연합뉴스 제목 4.5만, CC BY-SA 4.0
set -euo pipefail
cd "$(dirname "$0")/.."
RAW=data/public/raw
mkdir -p "$RAW"

fetch() {  # fetch <파일명> <URL>
  if [ -s "$RAW/$1" ]; then echo "skip $1"; return; fi
  curl -sfL --max-time 600 -o "$RAW/$1.part" "$2" && mv "$RAW/$1.part" "$RAW/$1"
  echo "ok   $1 ($(du -h "$RAW/$1" | cut -f1))"
}

fetch nsmc_ratings.txt       https://raw.githubusercontent.com/e9t/nsmc/master/ratings.txt
fetch kornli_multinli.tsv    https://raw.githubusercontent.com/kakaobrain/kor-nlu-datasets/master/KorNLI/multinli.train.ko.tsv
fetch kornli_snli.tsv        https://raw.githubusercontent.com/kakaobrain/kor-nlu-datasets/master/KorNLI/snli_1.0_train.ko.tsv
fetch korquad_v1_train.json  https://korquad.github.io/dataset/KorQuAD_v1.0_train.json
fetch klue_ynat_train.json   https://raw.githubusercontent.com/KLUE-benchmark/KLUE/main/klue_benchmark/ynat-v1.1/ynat-v1.1_train.json
echo done
