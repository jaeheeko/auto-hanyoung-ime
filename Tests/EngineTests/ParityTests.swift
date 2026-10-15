import XCTest
@testable import Engine

/// Python(tools/)과 Swift Engine의 동작 일치 검증. 벡터는 tools/make_vectors.py가 만든다.
final class ParityTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static let modelURL = root.appendingPathComponent("models/hanyoung.model")
    static let classifier: Classifier = { try! Model.load(url: modelURL) }()

    /// 모델은 저장소에 없다(학습 문서의 어휘가 들어간다). 없으면 판정 테스트는 건너뛴다.
    func requireModel() throws {
        let decide = Self.root.appendingPathComponent("Tests/vectors/decide.tsv")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.modelURL.path)
                          && FileManager.default.fileExists(atPath: decide.path),
                          "models/hanyoung.model 또는 Tests/vectors/decide.tsv 없음 — README의 모델 만들기 참고")
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

    func testPersonalOverlay() throws {
        try requireModel()
        // 개인 층은 공유 분류기를 바꾸므로 따로 로드한다
        let clf = try Model.load(url: Self.modelURL)
        let rare = "qjwmqlf"  // 버즈빌: 기본 모델에는 없거나 드문 어절
        let before = clf.decide(rare, prev: "KO").scores[.ko]!
        clf.applyPersonal(ko: [rare: 500], en: ["Buzzvil": 300], suffix: ["dptjsms": 20])
        let after = clf.decide(rare, prev: "KO").scores[.ko]!
        XCTAssertGreaterThan(after, before, "개인 사전에 더한 어절의 KO 점수가 올라야 한다")
        XCTAssertEqual(clf.decide("Buzzvildptjsms", prev: "KO").text, "Buzzvil에서는")
    }

    func testLearnGeneralizes() throws {
        try requireModel()
        let clf = try Model.load(url: Self.modelURL)
        // 영어 교정 한 번이 조사 변형과 대문자 변형에도 미쳐야 한다
        let w = "qlx"  // 기본 모델에 없는 영어 약어라고 치자 (한국어 가설 '빝'과 경쟁)
        XCTAssertNotEqual(clf.decide(w).label, .en, "학습 전에는 영어가 아니어야 실험이 의미 있다")
        clf.learn(keys: w, label: .en)
        XCTAssertEqual(clf.decide(w).label, .en)
        XCTAssertEqual(clf.decide(w + "dptj").text, "qlx에서")
        XCTAssertEqual(clf.decide("QLX").label, .en, "대소문자 접기로 대문자형도 영어")
        // 대문자 영어를 배워도 소문자형(sk=나)은 건드리지 않는다
        let ko = clf.decide("sk").text
        clf.learn(keys: "SK", label: .en)
        XCTAssertEqual(clf.decide("sk").text, ko)
        XCTAssertEqual(clf.decide("SKvmffoslt").text, "SK플래닛")
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
