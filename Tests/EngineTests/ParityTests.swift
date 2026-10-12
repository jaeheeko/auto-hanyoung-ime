import XCTest
@testable import Engine

/// Python(tools/)과 Swift Engine의 동작 일치 검증. 벡터는 tools/make_vectors.py가 만든다.
final class ParityTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static let modelURL = root.appendingPathComponent("models/hanyoung.json")
    static let classifier: Classifier = { try! Model.load(url: modelURL) }()

    /// 모델은 저장소에 없다(학습 문서의 어휘가 들어간다). 없으면 판정 테스트는 건너뛴다.
    func requireModel() throws {
        let decide = Self.root.appendingPathComponent("Tests/vectors/decide.tsv")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.modelURL.path)
                          && FileManager.default.fileExists(atPath: decide.path),
                          "models/hanyoung.json 또는 Tests/vectors/decide.tsv 없음 — README의 모델 만들기 참고")
    }

    func rows(_ name: String) throws -> [[String]] {
        let text = try String(contentsOf: Self.root.appendingPathComponent("Tests/vectors/\(name)"), encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    }

    func testAutomaton() throws {
        for r in try rows("automaton.tsv") {
            let c = Hangul.compose(r[0])
            XCTAssertEqual(c.text, r[1], "keys=\(r[0])")
            XCTAssertEqual(c.lone, Int(r[2])!, "lone keys=\(r[0])")
            XCTAssertEqual(c.shiftBad, Int(r[3])!, "shift keys=\(r[0])")
            if c.shiftBad == 0 {
                // 역변환: 한글만 있는 결과는 다시 같은 키가 되어야 한다
                XCTAssertEqual(Hangul.toKeys(c.text), r[0], "roundtrip keys=\(r[0])")
            }
        }
    }

    func testDecide() throws {
        try requireModel()
        let clf = Self.classifier
        var n = 0
        for r in try rows("decide.tsv") {
            let keys = r[0], prev = r[1], final = r[2] == "1"
            let d = clf.decide(keys, prev: prev, final: final)
            XCTAssertEqual(d.label.rawValue, r[3], "label keys=\(keys) prev=\(prev) final=\(final)")
            XCTAssertEqual(d.text, r[4], "text keys=\(keys) prev=\(prev) final=\(final)")
            for (i, l) in [Label.ko, .en, .mix].enumerated() {
                let expected = r[5 + i]
                let got = d.scores[l]!
                if expected == "-inf" {
                    XCTAssertEqual(got, -.infinity, "score \(l) keys=\(keys)")
                } else {
                    XCTAssertEqual(got, Double(expected)!, accuracy: 1e-4, "score \(l) keys=\(keys) prev=\(prev) final=\(final)")
                }
            }
            n += 1
        }
        XCTAssertGreaterThan(n, 100)
    }

    func testDecideSpeed() throws {
        try requireModel()
        let clf = Self.classifier
        let words = ["dkssudgktpdy", "Slackdptj", "standup", "gksrmf", "dlTtmqslek", "Temasek", "CJdhfflqmdud"]
        let t0 = Date()
        var count = 0
        for _ in 0..<200 {
            for w in words { _ = clf.decide(w, prev: "KO", final: false); count += 1 }
        }
        let perCall = Date().timeIntervalSince(t0) / Double(count) * 1000
        print("decide: \(String(format: "%.3f", perCall)) ms/call")
        XCTAssertLessThan(perCall, 1.0)
    }
}
