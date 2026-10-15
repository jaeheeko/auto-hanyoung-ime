import Foundation

public enum Label: String, CaseIterable, Codable {
    case ko = "KO"
    case en = "EN"
    case mix = "MIX"

    /// 되돌리기 순환: KO → EN → MIX(가능하면) → KO
    public func next(mixAvailable: Bool) -> Label {
        switch self {
        case .ko: return .en
        case .en: return mixAvailable ? .mix : .ko
        case .mix: return .ko
        }
    }
}

public struct Params {
    public var lonePenalty = 4.0
    public var shiftPenalty = 6.0
    public var maxSuffix = 24
    public var minPrefix = 1
    public var mixPenalty = 3.0
    public var suffixLambda = 0.7
    /// 접미에 조사·어미 사전(2회 이상)에 없는 음절이 있으면 벌점 (h싀, i홋 억제)
    public var suffixOOVPenalty = 8.0
    /// 자모 관용 표현(ㅋㅋ 등): 전체 어절 중 비중, 음절에 반복 자모가 붙을 확률, 3개째부터 글자당 비용
    public var jamoMass = 0.01
    public var runAttachProb = 0.02
    public var repeatDecay = 0.3
    /// 자모 관용 사전 (키열 → 상대 빈도). 모델 JSON에서 온다.
    public var jamoLex: [String: Double] = [:]
    /// 직전 라벨("BR"/"KO"/"EN"/"MIX") → 다음 라벨 log 사전확률
    public var prior: [String: [Label: Double]] = [:]
}

public struct Decision {
    public let label: Label
    public let texts: [Label: String]     // 가설별 렌더링 (MIX가 불가능하면 없음)
    public let scores: [Label: Double]
    public let split: Int                 // MIX 분할 위치, 아니면 -1
    public let margin: Double             // 1위 - 2위

    public var text: String { texts[label]! }
}

/// 어절 키 문자열에 대한 KO / EN / MIX 판정. tools/classify.py와 같다.
public final class Classifier {
    public let ko: WordModel
    public let en: WordModel
    public private(set) var suffixLM: CharLM
    public var params: Params
    private let jamoTotal: Double
    /// 접미(조사·어미) 빈도. 접미 n-gram은 작아서 여기서 바로 만들고, 개인 층을 더하면 다시 만든다.
    private var suffixCounts: [String: Double]
    /// 2회 이상 나온 접미를 조립한 음절 목록. 여기 없는 음절이 접미에 나오면 벌점.
    private var suffixSyllables: Set<Character> = []

    /// 음절 뒤·앞에 반복돼 붙는 자모 (ㅋ ㅎ ㅠ ㅜ)
    static let emoticonRunKeys: Set<Character> = Set("zgbn")

    init(ko: WordModel, en: WordModel, suffixCounts: [String: Double], params: Params) {
        self.ko = ko
        self.en = en
        self.params = params
        self.jamoTotal = params.jamoLex.values.reduce(0, +)
        self.suffixCounts = suffixCounts
        self.suffixLM = Classifier.buildSuffixLM(suffixCounts, order: ko.lm.order)
        self.suffixSyllables = Classifier.syllables(of: suffixCounts)
    }

    private static func buildSuffixLM(_ counts: [String: Double], order: Int) -> CharLM {
        let lm = CharLM(order: order)
        lm.train(counts)
        return lm
    }

    private static func syllables(of counts: [String: Double]) -> Set<Character> {
        var s: Set<Character> = []
        for (w, c) in counts where c >= 2 { s.formUnion(Hangul.compose(w).text) }
        return s
    }

    /// 개인 층: 본인 문서에서 뽑은 어절 빈도를 사전에 더하고 접미 n-gram을 다시 만든다.
    public func applyPersonal(ko koCounts: [String: Double], en enCounts: [String: Double], suffix: [String: Double]) {
        ko.addCounts(koCounts)
        en.addCounts(enCounts)
        if !suffix.isEmpty {
            for (w, c) in suffix { suffixCounts[w, default: 0] += c }
            suffixLM = Classifier.buildSuffixLM(suffixCounts, order: ko.lm.order)
            suffixSyllables = Classifier.syllables(of: suffixCounts)
        }
    }

    private static func trailingLoneCho(_ keys: String, _ text: String) -> Bool {
        guard let last = keys.last, let j = Hangul.jamoOfKey(last), Hangul.consonants.contains(j),
              let t = text.last, Hangul.isCompatJamo(t) else { return false }
        return true
    }

    /// KO 가설용 키열: QWERTOP 밖의 대문자는 소문자로.
    private static func canon(_ keys: String) -> String {
        String(keys.map { ch -> Character in
            (Hangul.shiftKeys.contains(ch) || !ch.isUppercase) ? ch : Character(ch.lowercased())
        })
    }

    /// 같은 키의 3회 이상 반복을 2회로 접는다. (접은 키열, 제거한 글자 수)
    static func collapseRuns(_ keys: String) -> (String, Int) {
        var out: [Character] = []
        var extra = 0
        for ch in keys {
            if out.count >= 2 && out[out.count - 1] == ch && out[out.count - 2] == ch {
                extra += 1
            } else {
                out.append(ch)
            }
        }
        return (String(out), extra)
    }

    /// emoticonRunKeys의 2회 이상 반복을 떼어 낸다. (나머지, run 길이들, 끝이 run인지)
    static func stripRuns(_ keys: String) -> (rest: String, runs: [Int], endsWithRun: Bool) {
        let chars = Array(keys)
        var rest: [Character] = []
        var runs: [Int] = []
        var endsWithRun = false
        var i = 0
        while i < chars.count {
            var j = i
            while j < chars.count && chars[j] == chars[i] { j += 1 }
            if emoticonRunKeys.contains(chars[i]) && j - i >= 2 {
                runs.append(j - i)
                endsWithRun = j == chars.count
            } else {
                rest.append(contentsOf: chars[i..<j])
                endsWithRun = false
            }
            i = j
        }
        return (String(rest), runs, endsWithRun)
    }

    /// 키열을 한국어 어절 하나로 보고 매긴 점수.
    private func koWordLoglik(_ keys: String, eos: Bool) -> (Double, String) {
        let c = Hangul.compose(keys)
        var lone = c.lone
        if !eos && Classifier.trailingLoneCho(keys, c.text) { lone -= 1 }  // 조합 중 말미의 초성은 정상
        var lp = ko.logprob(Classifier.canon(keys), eos: eos)
        lp -= params.lonePenalty * Double(lone) + params.shiftPenalty * Double(c.shiftBad)
        return (lp, c.text)
    }

    /// 자모 관용 표현(ㅋㅋ, 굿ㅠㅠ) 경로. 해당 없으면 nil.
    func emoticonLoglik(_ keys: String, final: Bool) -> Double? {
        let (collapsed, extra) = Classifier.collapseRuns(keys)
        if let w = params.jamoLex[collapsed] {
            return log(params.jamoMass * w / jamoTotal) - params.repeatDecay * Double(extra)
        }
        let (rest, runs, endsWithRun) = Classifier.stripRuns(keys)
        if runs.isEmpty { return nil }
        let runCost = runs.reduce(0.0) { $0 + log(params.runAttachProb) - params.repeatDecay * Double($1 - 2) }
        if rest.isEmpty { return log(params.jamoMass) + runCost }
        // 반복 자모가 끝에 있으면 앞의 어절은 완성된 것으로 본다
        let (lp, _) = koWordLoglik(rest, eos: final || endsWithRun)
        return lp + runCost
    }

    func koLoglik(_ keys: String, final: Bool) -> (Double, String) {
        var (lp, text) = koWordLoglik(keys, eos: final)
        if let alt = emoticonLoglik(keys, final: final), alt > lp { lp = alt }
        return (lp, text)
    }

    func enLoglik(_ keys: String, final: Bool) -> (Double, String) {
        (en.logprob(keys, eos: final), keys)
    }

    func suffixLoglik(_ suffix: String, final: Bool) -> (Double, String) {
        let c = Hangul.compose(suffix)
        var lone = c.lone
        if !final && Classifier.trailingLoneCho(suffix, c.text) { lone -= 1 }
        if lone > 0 || c.shiftBad > 0 { return (-.infinity, c.text) }
        let pSuf = exp(suffixLM.logprob(suffix, eos: final))
        let pNg = exp(ko.logprobNgram(suffix, eos: final))
        var lp = log(params.suffixLambda * pSuf + (1 - params.suffixLambda) * pNg)
        // 조합 중 말미의 초성은 아직 음절이 아니니 빼고 본다
        var body = Substring(c.text)
        if !final { while let t = body.last, Hangul.consonants.contains(t) { body.removeLast() } }
        if body.contains(where: { !suffixSyllables.contains($0) }) { lp -= params.suffixOOVPenalty }
        return (lp, c.text)
    }

    func mixLoglik(_ keys: String, final: Bool) -> (Double, String, Int) {
        var best: (Double, String, Int) = (-.infinity, "", -1)
        let chars = Array(keys)
        let n = chars.count
        let start = max(params.minPrefix, n - params.maxSuffix)
        if start >= n { return best }
        for i in start..<n {
            let prefix = String(chars[0..<i]), suffix = String(chars[i...])
            let letters = prefix.filter { $0 != "'" }
            guard !letters.isEmpty, letters.allSatisfy({ $0.isLetter }) else { continue }
            let (sLp, sText) = suffixLoglik(suffix, final: final)
            if sLp == -.infinity { continue }
            // 영어 접두는 완성된 단어이므로 항상 EOS 포함
            let lp = en.logprob(prefix) + sLp - params.mixPenalty
            if lp > best.0 { best = (lp, prefix + sText, i) }
        }
        return best
    }

    public func decide(_ keys: String, prev: String = "BR", bias: [Label: Double] = [:], final: Bool = true) -> Decision {
        let prior = params.prior[prev] ?? params.prior["BR"] ?? [:]
        let (koLp, koText) = koLoglik(keys, final: final)
        let (enLp, enText) = enLoglik(keys, final: final)
        let (mixLp, mixText, split) = mixLoglik(keys, final: final)
        var scores: [Label: Double] = [
            .ko: koLp + (prior[.ko] ?? 0),
            .en: enLp + (prior[.en] ?? 0),
            .mix: mixLp + (prior[.mix] ?? 0),
        ]
        for (l, v) in bias { scores[l]! += v }
        let ranked = Label.allCases.sorted { scores[$0]! > scores[$1]! }
        var texts: [Label: String] = [.ko: koText, .en: enText]
        if mixLp > -.infinity { texts[.mix] = mixText }
        return Decision(label: ranked[0], texts: texts, scores: scores,
                        split: ranked[0] == .mix ? split : -1,
                        margin: scores[ranked[0]]! - scores[ranked[1]]!)
    }
}
