import Foundation

/// 문자 n-gram 언어모델 (Witten-Bell 보간). tools/lm.py의 CharLM과 같다.
public final class CharLM {
    static let bos: Character = "\u{02}"
    static let eos: Character = "\u{03}"

    public let order: Int
    private var counts: [String: [Character: Double]] = [:]
    private var totals: [String: Double] = [:]
    private var types: [String: Double] = [:]
    private var vocab: Set<Character> = []
    private var vsize: Double = 1

    /// 빈 모델. train(_:)으로 채운다.
    public init(order: Int) {
        self.order = order
    }

    init(json: [String: Any]) throws {
        guard let order = json["order"] as? Int,
              let vocab = json["vocab"] as? String,
              let raw = json["counts"] as? [String: [String: Any]] else {
            throw ModelError.malformed("CharLM")
        }
        self.order = order
        self.vocab = Set(vocab)
        counts.reserveCapacity(raw.count)
        for (ctx, followers) in raw {
            var c: [Character: Double] = [:]
            for (k, v) in followers {
                guard let ch = k.first, let n = (v as? NSNumber)?.doubleValue else { continue }
                c[ch] = n
            }
            counts[ctx] = c
        }
        finalize()
    }

    /// 어절 빈도로 학습한다. tools/lm.py CharLM.train과 같은 카운트를 만든다.
    public func train(_ words: [String: Double]) {
        let pad = [Character](repeating: CharLM.bos, count: order - 1)
        for (w, wt) in words {
            let s = pad + Array(w) + [CharLM.eos]
            for i in (order - 1)..<s.count {
                let ch = s[i]
                vocab.insert(ch)
                for k in 0..<order {
                    let ctx = String(s[(i - k)..<i])
                    counts[ctx, default: [:]][ch, default: 0] += wt
                }
            }
        }
        finalize()
    }

    private func finalize() {
        totals = counts.mapValues { $0.values.reduce(0, +) }
        types = counts.mapValues { Double($0.count) }
        vsize = Double(vocab.count) + 1
    }

    func prob(ctx: ArraySlice<Character>, ch: Character) -> Double {
        var p = 1.0 / vsize
        let n = ctx.count
        for k in 0...n {
            let c = k == 0 ? "" : String(ctx[(ctx.endIndex - k)...])
            guard let counter = counts[c] else { break }
            let total = totals[c]!, t = types[c]!
            p = ((counter[ch] ?? 0) + t * p) / (total + t)
        }
        return p
    }

    /// eos=false면 조합 중인 접두로 본다.
    public func logprob(_ word: String, eos: Bool = true) -> Double {
        var s = [Character](repeating: CharLM.bos, count: order - 1)
        s.append(contentsOf: word)
        if eos { s.append(CharLM.eos) }
        var lp = 0.0
        for i in (order - 1)..<s.count {
            lp += log(prob(ctx: s[(i - order + 1)..<i], ch: s[i]))
        }
        return lp
    }
}

/// 어휘 사전(빈도)과 문자 n-gram을 혼합한 어절 확률.
public final class WordModel {
    public let lm: CharLM
    private(set) var lex: [String: Double]
    private(set) var total: Double
    let lam: Double
    let caseFold: Bool
    let foldWeight: Double

    init(lm: CharLM, lex: [String: Double], total: Double, lam: Double, caseFold: Bool, foldWeight: Double) {
        self.lm = lm
        self.lex = lex
        self.total = total
        self.lam = lam
        self.caseFold = caseFold
        self.foldWeight = foldWeight
    }

    /// 개인 층: 어휘 사전에 빈도를 더한다. n-gram은 건드리지 않는다.
    public func addCounts(_ counts: [String: Double]) {
        for (w, c) in counts { lex[w, default: 0] += c }
        total = lex.values.reduce(0, +)
    }

    private func prob(_ word: String, eos: Bool) -> Double {
        let pNg = exp(lm.logprob(word, eos: eos))
        if !eos { return pNg }
        let pLex = total > 0 ? (lex[word] ?? 0) / total : 0
        return lam * pLex + (1 - lam) * pNg
    }

    public func logprob(_ word: String, eos: Bool = true) -> Double {
        var p = prob(word, eos: eos)
        if caseFold {
            let lower = word.lowercased()
            if lower != word { p = max(p, foldWeight * prob(lower, eos: eos)) }
        }
        return log(p)
    }

    public func logprobNgram(_ word: String, eos: Bool = true) -> Double {
        lm.logprob(word, eos: eos)
    }
}

public enum ModelError: Error {
    case malformed(String)
}
