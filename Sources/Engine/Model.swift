import Foundation

/// tools/export_model.py가 만든 바이너리 모델(.model)을 읽어 Classifier를 만든다.
public enum Model {
    static let magic: [UInt8] = Array("HYM1".utf8)

    public static func load(url: URL) throws -> Classifier {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        var reader = BinaryReader(data)
        guard Array(try reader.bytes(4)) == magic else { throw ModelError.malformed("magic") }
        let headerLen = Int(try reader.u32())
        guard let header = try JSONSerialization.jsonObject(with: reader.bytes(headerLen)) as? [String: Any],
              let p = header["params"] as? [String: Any] else {
            throw ModelError.malformed("header")
        }
        func num(_ v: Any?, _ d: Double) -> Double { (v as? NSNumber)?.doubleValue ?? d }
        func lex(_ raw: [String: Any]) -> [String: Double] {
            var d: [String: Double] = [:]
            d.reserveCapacity(raw.count)
            for (k, v) in raw { if let n = (v as? NSNumber)?.doubleValue { d[k] = n } }
            return d
        }

        var params = Params()
        params.lonePenalty = num(p["lone_penalty"], params.lonePenalty)
        params.shiftPenalty = num(p["shift_penalty"], params.shiftPenalty)
        params.maxSuffix = Int(num(p["max_suffix"], Double(params.maxSuffix)))
        params.minPrefix = Int(num(p["min_prefix"], Double(params.minPrefix)))
        params.mixPenalty = num(p["mix_penalty"], params.mixPenalty)
        params.suffixLambda = num(p["suffix_lambda"], params.suffixLambda)
        params.jamoMass = num(p["jamo_mass"], params.jamoMass)
        params.runAttachProb = num(p["run_attach_prob"], params.runAttachProb)
        params.repeatDecay = num(p["repeat_decay"], params.repeatDecay)
        if let jamo = p["jamo_lex"] as? [String: Any] { params.jamoLex = lex(jamo) }
        if let prior = p["prior"] as? [String: [String: Any]] {
            for (prev, dist) in prior {
                var d: [Label: Double] = [:]
                for (l, v) in dist { if let label = Label(rawValue: l) { d[label] = num(v, 0) } }
                params.prior[prev] = d
            }
        }
        let suffixCounts = lex((header["suffix_counts"] as? [String: Any]) ?? [:])

        let koLM = try CharLM(reader: &reader)
        let enLM = try CharLM(reader: &reader)
        let ko = try WordModel(lm: koLM, reader: &reader, lam: num(p["lex_lambda_ko"], 0.5),
                               caseFold: false, foldWeight: 0)
        let en = try WordModel(lm: enLM, reader: &reader, lam: num(p["lex_lambda_en"], 0.5),
                               caseFold: true, foldWeight: num(p["fold_weight"], 0.3))
        return Classifier(ko: ko, en: en, suffixCounts: suffixCounts, params: params)
    }

    /// tools/personalize.py가 만든 개인 어휘 층. {"ko": {...}, "en": {...}, "suffix": {...}}
    public struct PersonalLexicon {
        public let ko: [String: Double]
        public let en: [String: Double]
        public let suffix: [String: Double]

        public static func load(url: URL) throws -> PersonalLexicon {
            let data = try Data(contentsOf: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ModelError.malformed("user_lexicon")
            }
            func section(_ k: String) -> [String: Double] {
                var d: [String: Double] = [:]
                for (w, v) in (json[k] as? [String: Any]) ?? [:] { if let n = (v as? NSNumber)?.doubleValue { d[w] = n } }
                return d
            }
            return PersonalLexicon(ko: section("ko"), en: section("en"), suffix: section("suffix"))
        }
    }
}
