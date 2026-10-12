import Foundation

/// tools/export_model.py가 만든 JSON을 읽어 Classifier를 만든다.
public enum Model {
    public static func load(url: URL) throws -> Classifier {
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ModelError.malformed("root")
        }
        return try build(json)
    }

    static func build(_ json: [String: Any]) throws -> Classifier {
        guard let p = json["params"] as? [String: Any],
              let koLM = json["ko_lm"] as? [String: Any],
              let enLM = json["en_lm"] as? [String: Any],
              let sufLM = json["suffix_lm"] as? [String: Any],
              let koLexRaw = json["ko_lex"] as? [String: Any],
              let enLexRaw = json["en_lex"] as? [String: Any] else {
            throw ModelError.malformed("sections")
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

        let ko = WordModel(lm: try CharLM(json: koLM), lex: lex(koLexRaw),
                           total: num(json["ko_lex_total"], 0), lam: num(p["lex_lambda_ko"], 0.5),
                           caseFold: false, foldWeight: 0)
        let en = WordModel(lm: try CharLM(json: enLM), lex: lex(enLexRaw),
                           total: num(json["en_lex_total"], 0), lam: num(p["lex_lambda_en"], 0.5),
                           caseFold: true, foldWeight: num(p["fold_weight"], 0.3))
        return Classifier(ko: ko, en: en, suffixLM: try CharLM(json: sufLM), params: params)
    }
}
