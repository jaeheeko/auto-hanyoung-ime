import Foundation

/// 문자 n-gram 언어모델 (Witten-Bell 보간). tools/lm.py의 CharLM과 같다.
///
/// 두 가지 저장 방식이 있다.
/// - 해시 테이블: 모델 파일에서 읽은 큰 모델. 문맥·다음 문자를 FNV 해시로 찾는다.
/// - 딕셔너리: train(_:)으로 만든 작은 모델(접미 n-gram).
public final class CharLM {
    static let bos: Character = "\u{02}"
    static let eos: Character = "\u{03}"

    public let order: Int
    private var vsize: Double = 1

    // 해시 테이블 저장
    private var ctxTable: SortedTable<Int>? = nil      // 문맥 해시 → 인덱스
    private var ctxTotals: [Double] = []
    private var ctxTypes: [UInt32] = []
    private var followers: SortedTable<Float>? = nil   // fnv(ctx + "\0" + ch) → 카운트

    // 딕셔너리 저장
    private var counts: [String: [Character: Double]] = [:]
    private var totals: [String: Double] = [:]
    private var types: [String: Double] = [:]
    private var vocab: Set<Character> = []

    /// 빈 모델. train(_:)으로 채운다.
    public init(order: Int) {
        self.order = order
    }

    /// 모델 파일의 n-gram 섹션을 읽는다.
    init(reader: inout BinaryReader) throws {
        reader.align8()
        order = Int(try reader.u32())
        vsize = Double(try reader.u32())
        let nCtx = Int(try reader.u32())
        let nFol = Int(try reader.u32())
        let ctxKeys = try reader.array(UInt64.self, count: nCtx)
        ctxTotals = try reader.array(Double.self, count: nCtx)
        ctxTypes = try reader.array(UInt32.self, count: nCtx)
        reader.align8()
        let folKeys = try reader.array(UInt64.self, count: nFol)
        let folVals = try reader.array(Float.self, count: nFol)
        ctxTable = SortedTable(keys: ctxKeys, values: Array(0..<nCtx))
        followers = SortedTable(keys: folKeys, values: folVals)
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
        totals = counts.mapValues { $0.values.reduce(0, +) }
        types = counts.mapValues { Double($0.count) }
        vsize = Double(vocab.count) + 1
    }

    func prob(ctx: ArraySlice<Character>, ch: Character) -> Double {
        var p = 1.0 / vsize
        let n = ctx.count
        if let ctxTable = ctxTable, let followers = followers {
            for k in 0...n {
                let c = ctx[(ctx.endIndex - k)...]
                guard let i = ctxTable[FNV.hash(c)] else { break }
                let total = ctxTotals[i], t = Double(ctxTypes[i])
                let cnt = Double(followers[FNV.hash(c, then: ch)] ?? 0)
                p = (cnt + t * p) / (total + t)
            }
        } else {
            for k in 0...n {
                let c = k == 0 ? "" : String(ctx[(ctx.endIndex - k)...])
                guard let counter = counts[c] else { break }
                let total = totals[c]!, t = types[c]!
                p = ((counter[ch] ?? 0) + t * p) / (total + t)
            }
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
    private let base: SortedTable<Float>          // 모델 파일의 사전 (단어 해시 → 빈도)
    private var overlay: [UInt64: Double] = [:]   // 개인 층
    private(set) var total: Double
    let lam: Double
    let caseFold: Bool
    let foldWeight: Double

    init(lm: CharLM, reader: inout BinaryReader, lam: Double, caseFold: Bool, foldWeight: Double) throws {
        self.lm = lm
        reader.align8()
        let n = Int(try reader.u32())
        _ = try reader.u32()
        total = try reader.f64()
        let keys = try reader.array(UInt64.self, count: n)
        let vals = try reader.array(Float.self, count: n)
        base = SortedTable(keys: keys, values: vals)
        self.lam = lam
        self.caseFold = caseFold
        self.foldWeight = foldWeight
    }

    /// 개인 층: 어휘 사전에 빈도를 더한다. n-gram은 건드리지 않는다.
    public func addCounts(_ counts: [String: Double]) {
        for (w, c) in counts {
            overlay[FNV.hash(w), default: 0] += c
            total += c
        }
    }

    private func count(_ word: String) -> Double {
        let h = FNV.hash(word)
        return Double(base[h] ?? 0) + (overlay[h] ?? 0)
    }

    private func prob(_ word: String, eos: Bool) -> Double {
        let pNg = exp(lm.logprob(word, eos: eos))
        if !eos { return pNg }
        let pLex = total > 0 ? count(word) / total : 0
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
