#!/bin/bash
# 영어 모델 학습에 쓰는 외부 데이터를 data/external/ 에 내려받는다.
# - en_50k.txt: hermitdave/FrequencyWords (OpenSubtitles 기반 영어 단어 빈도표, CC BY-SA 4.0)
#   https://github.com/hermitdave/FrequencyWords
# 내려받은 데이터는 로컬 모델 학습에만 쓰이며 저장소에는 포함되지 않는다.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p data/external
if [ ! -s data/external/en_50k.txt ]; then
  curl -sfL --max-time 60 -o data/external/en_50k.txt \
    https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/en/en_50k.txt
  echo "downloaded data/external/en_50k.txt ($(wc -l < data/external/en_50k.txt) lines)"
else
  echo "data/external/en_50k.txt already present"
fi
