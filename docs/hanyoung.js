/* Auto HanYoung 판정기의 JavaScript 이식. tools/classify.py·lm.py·hangul.py와 동작이 같아야 한다.
   모델은 tools/export_demo.py가 만든 JSON. 브라우저와 Node 양쪽에서 쓴다. */
(function (root) {
  "use strict";
  const BOS = "\u0002", EOS = "\u0003";

  // ---------- 두벌식 오토마타 ----------
  const CHO = "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ";
  const JUNG = "ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ";
  const JONG = "ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ";
  const KEY_TO_JAMO = {
    r: "ㄱ", R: "ㄲ", s: "ㄴ", e: "ㄷ", E: "ㄸ", f: "ㄹ", a: "ㅁ", q: "ㅂ", Q: "ㅃ", t: "ㅅ", T: "ㅆ",
    d: "ㅇ", w: "ㅈ", W: "ㅉ", c: "ㅊ", z: "ㅋ", x: "ㅌ", v: "ㅍ", g: "ㅎ",
    k: "ㅏ", o: "ㅐ", i: "ㅑ", O: "ㅒ", j: "ㅓ", p: "ㅔ", u: "ㅕ", P: "ㅖ", h: "ㅗ", y: "ㅛ",
    n: "ㅜ", b: "ㅠ", m: "ㅡ", l: "ㅣ",
  };
  const SHIFT_KEYS = new Set("QWERTOP");
  const JAMO_TO_KEYS = {};
  for (const k in KEY_TO_JAMO) JAMO_TO_KEYS[KEY_TO_JAMO[k]] = k;
  Object.assign(JAMO_TO_KEYS, { "ㅘ": "hk", "ㅙ": "ho", "ㅚ": "hl", "ㅝ": "nj", "ㅞ": "np", "ㅟ": "nl", "ㅢ": "ml",
    "ㄳ": "rt", "ㄵ": "sw", "ㄶ": "sg", "ㄺ": "fr", "ㄻ": "fa", "ㄼ": "fq", "ㄽ": "ft", "ㄾ": "fx", "ㄿ": "fv", "ㅀ": "fg", "ㅄ": "qt" });
  const COMPOUND_JUNG = { "ㅗㅏ": "ㅘ", "ㅗㅐ": "ㅙ", "ㅗㅣ": "ㅚ", "ㅜㅓ": "ㅝ", "ㅜㅔ": "ㅞ", "ㅜㅣ": "ㅟ", "ㅡㅣ": "ㅢ" };
  const COMPOUND_JONG = { "ㄱㅅ": "ㄳ", "ㄴㅈ": "ㄵ", "ㄴㅎ": "ㄶ", "ㄹㄱ": "ㄺ", "ㄹㅁ": "ㄻ", "ㄹㅂ": "ㄼ", "ㄹㅅ": "ㄽ", "ㄹㅌ": "ㄾ", "ㄹㅍ": "ㄿ", "ㄹㅎ": "ㅀ", "ㅂㅅ": "ㅄ" };
  const SPLIT_JONG = {};
  for (const k in COMPOUND_JONG) SPLIT_JONG[COMPOUND_JONG[k]] = k;
  const JONG_OK = new Set(JONG);
  const CONSONANTS = new Set(CHO);
  const idx = (s) => { const m = {}; for (let i = 0; i < s.length; i++) m[s[i]] = i; return m; };
  const CHO_INDEX = idx(CHO), JUNG_INDEX = idx(JUNG), JONG_INDEX = idx(JONG);

  const isUpper = (ch) => ch >= "A" && ch <= "Z";
  const isSyllable = (ch) => ch >= "가" && ch <= "힣";
  const isCompatJamo = (ch) => ch >= "ㄱ" && ch <= "ㅣ";
  const isHangul = (ch) => isSyllable(ch) || isCompatJamo(ch);

  function jamoOfKey(ch) {
    let j = KEY_TO_JAMO[ch];
    if (j === undefined && isUpper(ch)) j = KEY_TO_JAMO[ch.toLowerCase()];
    return j;
  }

  function toKeys(text) {
    let out = "";
    for (const ch of text) {
      if (isSyllable(ch)) {
        const code = ch.charCodeAt(0) - 0xAC00;
        const cho = Math.floor(code / 588), jung = Math.floor((code % 588) / 28), jong = code % 28;
        out += JAMO_TO_KEYS[CHO[cho]] + JAMO_TO_KEYS[JUNG[jung]];
        if (jong) out += JAMO_TO_KEYS[JONG[jong - 1]];
      } else if (isCompatJamo(ch)) out += JAMO_TO_KEYS[ch] || ch;
      else out += ch;
    }
    return out;
  }

  /** 키열을 두벌식으로 조립한다. {text, lone, shiftBad} */
  function compose(keys) {
    let out = "", cho = null, jung = null, jong = null, lone = 0, shiftBad = 0;
    const flush = () => {
      if (cho === null && jung === null) return;
      if (cho !== null && jung !== null) {
        let code = 0xAC00 + CHO_INDEX[cho] * 588 + JUNG_INDEX[jung] * 28;
        if (jong !== null) code += JONG_INDEX[jong] + 1;
        out += String.fromCharCode(code);
      } else { out += cho !== null ? cho : jung; lone++; }
      cho = jung = jong = null;
    };
    for (const ch of keys) {
      const j = jamoOfKey(ch);
      if (j === undefined) { flush(); out += ch; continue; }
      if (isUpper(ch) && !SHIFT_KEYS.has(ch)) shiftBad++;
      if (CONSONANTS.has(j)) {
        if (jung === null) { if (cho !== null) flush(); cho = j; }
        else if (cho === null) { flush(); cho = j; }
        else if (jong === null) { if (JONG_OK.has(j)) jong = j; else { flush(); cho = j; } }
        else { const comp = COMPOUND_JONG[jong + j]; if (comp) jong = comp; else { flush(); cho = j; } }
      } else {
        if (jung === null) jung = j;
        else if (jong === null) { const comp = COMPOUND_JUNG[jung + j]; if (comp) jung = comp; else { flush(); jung = j; } }
        else if (SPLIT_JONG[jong]) { const pair = SPLIT_JONG[jong]; jong = pair[0]; flush(); cho = pair[1]; jung = j; }
        else { const moved = jong; jong = null; flush(); cho = moved; jung = j; }
      }
    }
    flush();
    return { text: out, lone, shiftBad };
  }

  // ---------- 문자 n-gram (Witten-Bell) ----------
  class CharLM {
    constructor(order) { this.order = order; this.counts = {}; this.vocab = new Set(); this.finalize(); }
    static fromJSON(d) {
      const lm = new CharLM(d.order);
      lm.counts = d.counts;
      lm.vocab = new Set(d.vocab);
      lm.finalize();
      return lm;
    }
    train(counts) {  // {word: weight}
      const pad = BOS.repeat(this.order - 1);
      for (const w in counts) {
        const wt = counts[w], s = pad + w + EOS;
        for (let i = this.order - 1; i < s.length; i++) {
          const ch = s[i];
          this.vocab.add(ch);
          for (let k = 0; k < this.order; k++) {
            const ctx = s.slice(i - k, i);
            (this.counts[ctx] || (this.counts[ctx] = {}))[ch] = (this.counts[ctx][ch] || 0) + wt;
          }
        }
      }
      this.finalize();
    }
    finalize() {
      this.totals = {}; this.types = {};
      for (const ctx in this.counts) {
        let n = 0, t = 0;
        for (const ch in this.counts[ctx]) { n += this.counts[ctx][ch]; t++; }
        this.totals[ctx] = n; this.types[ctx] = t;
      }
      this.vsize = this.vocab.size + 1;
    }
    prob(ctx, ch) {
      let p = 1 / this.vsize;
      for (let k = 0; k <= ctx.length; k++) {
        const c = k ? ctx.slice(ctx.length - k) : "";
        const counter = this.counts[c];
        if (counter === undefined) break;
        const n = this.totals[c], t = this.types[c];
        p = ((counter[ch] || 0) + t * p) / (n + t);
      }
      return p;
    }
    logprob(word, eos) {
      const s = BOS.repeat(this.order - 1) + word + (eos ? EOS : "");
      let lp = 0;
      for (let i = this.order - 1; i < s.length; i++) lp += Math.log(this.prob(s.slice(i - this.order + 1, i), s[i]));
      return lp;
    }
  }

  class WordModel {
    constructor(lm, lex, lam, caseFold, foldWeight) {
      // 프로토타입을 끊는다. 안 그러면 valueOf·toString 같은 입력이 Object.prototype의 함수를 찾아 NaN이 된다.
      this.lm = lm; this.lex = Object.setPrototypeOf(lex, null); this.lam = lam; this.caseFold = caseFold; this.foldWeight = foldWeight || 0.3;
      this.total = 0;
      for (const w in lex) this.total += lex[w];
    }
    addCounts(counts) { for (const w in counts) { this.lex[w] = (this.lex[w] || 0) + counts[w]; this.total += counts[w]; } }
    _prob(word, eos) {
      const pNg = Math.exp(this.lm.logprob(word, eos));
      if (!eos) return pNg;
      const pLex = this.total ? (this.lex[word] || 0) / this.total : 0;
      return this.lam * pLex + (1 - this.lam) * pNg;
    }
    logprob(word, eos) {
      let p = this._prob(word, eos);
      if (this.caseFold && word !== word.toLowerCase() && /[A-Z]/.test(word)) p = Math.max(p, this.foldWeight * this._prob(word.toLowerCase(), eos));
      return Math.log(p);
    }
    logprobNgram(word, eos) { return this.lm.logprob(word, eos); }
  }

  // ---------- 판정기 ----------
  const EMOTICON_RUN_KEYS = new Set("zgbn");
  const LABELS = ["KO", "EN", "MIX"];
  // 어절 안의 따옴표. 점수를 매길 때는 떼고 보고, 렌더링에는 그대로 남긴다.
  const QUOTES = new Set("'\"");
  const stripQuotes = (keys) => { let o = ""; for (const c of keys) if (!QUOTES.has(c)) o += c; return o; };
  /** 따옴표를 뗀 키열의 분할점을 원래 키열의 인덱스로. 분할점 바로 뒤의 따옴표는 접두에 붙인다 ('빛'을). */
  function unstripIndex(keys, split) {
    let cnt = 0, j = 0;
    while (j < keys.length && cnt < split) { if (!QUOTES.has(keys[j])) cnt++; j++; }
    while (j < keys.length - 1 && QUOTES.has(keys[j])) j++;
    return j;
  }
  // 영어 단어 뒤에 붙는 조사·서술격 꼬리. 앱의 UserDict.particles와 같다.
  const PARTICLES = new Set(`
    은 는 이 가 을 를 의 에 에서 로 으로 와 과 도 만 부터 까지 처럼 보다 께서 에게 한테 랑 이랑 라는 이라는 라고 이라고
    로서 로써 으로서 으로써 마다 조차 밖에 뿐 대로 에서는 에는 에도 로는 으로는 로도 으로도 와는 과는 와도 과도
    요 은요 는요 이요 이나 나 이란 란 이든 든 이며 며 하고 에게는 에게도 한테는 한테도 께 께는 로의 으로의 에서의 와의 과의
    이라면 라면 이라서 라서 이라도 라도 이야 야 이고 고 인데 인 임 입니다 이다 였다 이었다 이지 지 이죠 죠 이네 네 이면 면
  `.trim().split(/\s+/));

  function collapseRuns(keys) {
    let out = "", extra = 0;
    for (const ch of keys) {
      if (out.length >= 2 && out[out.length - 1] === ch && out[out.length - 2] === ch) extra++;
      else out += ch;
    }
    return [out, extra];
  }
  function stripRuns(keys) {
    let rest = "", runs = [], endsWithRun = false, i = 0;
    const n = keys.length;
    while (i < n) {
      let j = i;
      while (j < n && keys[j] === keys[i]) j++;
      if (EMOTICON_RUN_KEYS.has(keys[i]) && j - i >= 2) { runs.push(j - i); endsWithRun = j === n; }
      else { rest += keys.slice(i, j); endsWithRun = false; }
      i = j;
    }
    return [rest, runs, endsWithRun];
  }

  class Classifier {
    constructor(model) {
      this.p = model.params;
      Object.setPrototypeOf(this.p.jamo_lex, null);
      this.jamoTotal = 0;
      for (const k in this.p.jamo_lex) this.jamoTotal += this.p.jamo_lex[k];
      this.ko = new WordModel(CharLM.fromJSON(model.ko), model.ko.lex, model.ko.lam, false, 0);
      this.en = new WordModel(CharLM.fromJSON(model.en), model.en.lex, model.en.lam, true, model.en.fold_weight);
      this.suffixCounts = Object.assign({}, model.suffix);
      this.buildSuffix();
    }
    buildSuffix() {
      this.suffixLM = new CharLM(this.ko.lm.order);
      this.suffixLM.train(this.suffixCounts);
      this.suffixSyllables = new Set();
      for (const w in this.suffixCounts) if (this.suffixCounts[w] >= 2) for (const ch of compose(w).text) this.suffixSyllables.add(ch);
    }
    /** 사용자가 고친 어절을 어휘 덧층에 더한다 (앱의 Classifier.learn과 같다) */
    learn(keys, label, split, weight) {
      weight = weight || 20;
      if (label === "EN") this.en.addCounts({ [keys]: weight });
      else if (label === "KO") this.ko.addCounts({ [Classifier.canon(keys)]: weight });
      else { const i = split != null ? split : this.decide(keys).split; if (i > 0) this.en.addCounts({ [stripQuotes(keys.slice(0, i))]: weight }); }
    }
    static canon(keys) {
      let out = "";
      for (const c of keys) out += (SHIFT_KEYS.has(c) || !isUpper(c)) ? c : c.toLowerCase();
      return out;
    }
    static trailingLoneCho(keys, text) {
      return keys.length > 0 && CONSONANTS.has(jamoOfKey(keys[keys.length - 1])) && text.length > 0 && isCompatJamo(text[text.length - 1]);
    }
    koWordLoglik(keys, eos) {
      const c = compose(keys);
      let lone = c.lone;
      if (!eos && Classifier.trailingLoneCho(keys, c.text)) lone--;
      let lp = this.ko.logprob(Classifier.canon(keys), eos);
      lp -= this.p.lone_penalty * lone + this.p.shift_penalty * c.shiftBad;
      return [lp, c.text];
    }
    emoticonLoglik(keys, final) {
      const p = this.p;
      const [collapsed, extra] = collapseRuns(keys);
      const w = p.jamo_lex[collapsed];
      if (w !== undefined) return Math.log(p.jamo_mass * w / this.jamoTotal) - p.repeat_decay * extra;
      const [rest, runs, endsWithRun] = stripRuns(keys);
      if (!runs.length) return null;
      let runCost = 0;
      for (const n of runs) runCost += Math.log(p.run_attach_prob) - p.repeat_decay * (n - 2);
      if (!rest) return Math.log(p.jamo_mass) + runCost;
      return this.koWordLoglik(rest, final || endsWithRun)[0] + runCost;
    }
    koLoglik(keys, final) {
      let [lp, text] = this.koWordLoglik(keys, final);
      const alt = this.emoticonLoglik(keys, final);
      if (alt !== null && alt > lp) lp = alt;
      return [lp, text];
    }
    enLoglik(keys, final) { return [this.en.logprob(keys, final), keys]; }
    suffixLoglik(suffix, final) {
      const c = compose(suffix);
      let lone = c.lone;
      if (!final && Classifier.trailingLoneCho(suffix, c.text)) lone--;
      if (lone > 0 || c.shiftBad > 0) return [-Infinity, c.text];
      const pSuf = Math.exp(this.suffixLM.logprob(suffix, final));
      const pNg = Math.exp(this.ko.logprobNgram(suffix, final));
      let lp = Math.log(this.p.suffix_lambda * pSuf + (1 - this.p.suffix_lambda) * pNg);
      let body = c.text;
      if (!final) while (body.length && CONSONANTS.has(body[body.length - 1])) body = body.slice(0, -1);
      for (const ch of body) if (!this.suffixSyllables.has(ch)) { lp -= this.p.suffix_oov_penalty; break; }
      return [lp, c.text];
    }
    mixLoglik(keys, final) {
      let best = [-Infinity, "", -1];
      const n = keys.length;
      for (let i = Math.max(this.p.min_prefix, n - this.p.max_suffix); i < n; i++) {
        const prefix = keys.slice(0, i), suffix = keys.slice(i);
        const letters = stripQuotes(prefix);
        if (!/^[A-Za-z]+$/.test(letters)) continue;
        let penalty = this.p.mix_penalty;
        // 소문자 접두의 MIX 억제(cot과의, cof시네). 1글자·대문자 접두는 그대로.
        if (letters.length >= 2 && /^[a-z]+$/.test(letters)) {
          const c = this.en.lex[letters] || 0;
          const short = letters.length <= (this.p.short_prefix_max_len ?? 3);
          if (c <= 0 && short) continue;
          if (c <= 0 || (short && c < (this.p.short_prefix_min_count ?? 5))) penalty += this.p.short_prefix_penalty ?? 8;
        }
        const [sLp, sText] = this.suffixLoglik(suffix, final);
        if (sLp === -Infinity) continue;
        const lp = this.en.logprob(prefix, true) + sLp - penalty;
        if (lp > best[0]) best = [lp, prefix + sText, i];
      }
      return best;
    }
    /** 어절 판정. prev: 직전 라벨("BR"|"KO"|"EN"|"MIX"), bias: {라벨: 가산점}, final: 어절이 끝났는지 */
    decide(keys, prev, bias, final) {
      if (prev === undefined) prev = "BR";
      if (final === undefined) final = true;
      const prior = this.p.prior[prev] || this.p.prior.BR || {};
      let koLp, koText, enLp, enText, mixLp, mixText, split;
      const stripped = stripQuotes(keys);
      if (stripped && stripped.length !== keys.length) {
        // 따옴표는 점수에서 빼고 렌더링에만 남긴다
        koLp = this.koLoglik(stripped, final)[0];
        koText = compose(keys).text;
        enLp = Math.max(this.en.logprob(keys, final), this.en.logprob(stripped, final));
        enText = keys;
        const m = this.mixLoglik(stripped, final);
        mixLp = m[0];
        if (m[2] > 0) { split = unstripIndex(keys, m[2]); mixText = keys.slice(0, split) + compose(keys.slice(split)).text; }
        else { split = -1; mixText = ""; }
      } else {
        [koLp, koText] = this.koLoglik(keys, final);
        [enLp, enText] = this.enLoglik(keys, final);
        [mixLp, mixText, split] = this.mixLoglik(keys, final);
      }
      const scores = { KO: koLp + (prior.KO || 0), EN: enLp + (prior.EN || 0), MIX: mixLp + (prior.MIX || 0) };
      if (bias) for (const k in bias) scores[k] += bias[k];
      const ranked = LABELS.slice().sort((a, b) => scores[b] - scores[a]);
      const texts = { KO: koText, EN: enText };
      if (mixLp > -Infinity) texts.MIX = mixText;
      const label = ranked[0];
      // split은 MIX 가설이 있으면 1위가 아니어도 그 분할 위치 (되돌리기로 MIX를 고른 뒤 학습할 때 쓴다)
      return { label, text: texts[label], texts, scores, split: mixLp > -Infinity ? split : -1, margin: scores[ranked[0]] - scores[ranked[1]] };
    }
  }

  const api = { compose, toKeys, isHangul, isSyllable, CharLM, WordModel, Classifier, LABELS, PARTICLES };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.Hanyoung = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
