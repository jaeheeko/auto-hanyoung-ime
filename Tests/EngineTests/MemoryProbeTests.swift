import XCTest
import Darwin
@testable import Engine

/// 모델 메모리 측정. 기본으로는 건너뛰고, 환경변수를 주면 phys_footprint(활성 상태 모니터의 "메모리")를 찍는다.
///   HANYOUNG_PROBE_MODEL=models/hanyoung.model HANYOUNG_PROBE_LEX=~/Library/Application\ Support/Hanyoung/user_lexicon.json \
///   swift test --filter MemoryProbeTests 2>&1 | grep PROBE
/// 모델 로드 전/후, 개인 층 적용 후의 증가량과 로드 시간, 판정 1회 시간을 출력한다. 모델 변형을 비교할 때 쓴다.
final class MemoryProbeTests: XCTestCase {
    func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    func testProbe() throws {
        let env = ProcessInfo.processInfo.environment
        guard let modelPath = env["HANYOUNG_PROBE_MODEL"] else { throw XCTSkip("HANYOUNG_PROBE_MODEL 없음") }
        let words = ["gksrmf", "hello", "Slackdptj", "dkssudgktpdy", "the", "tn", "zzz", "Githubdp", "wjdaksdlfy", "programming"]
        let before = footprintMB()
        let t0 = Date()
        let clf = try Model.load(url: URL(fileURLWithPath: modelPath))
        let loadMs = Date().timeIntervalSince(t0) * 1000
        for w in words { _ = clf.decide(w, prev: "KO", final: true) }
        let afterModel = footprintMB()
        var afterPersonal = afterModel
        var personalMs = 0.0
        if let lexPath = env["HANYOUNG_PROBE_LEX"] {
            let t1 = Date()
            let p = try Model.PersonalLexicon.load(url: URL(fileURLWithPath: lexPath))
            clf.applyPersonal(ko: p.ko, en: p.en, suffix: p.suffix)
            personalMs = Date().timeIntervalSince(t1) * 1000
            for w in words { _ = clf.decide(w, prev: "KO", final: true) }
            afterPersonal = footprintMB()
        }
        let t2 = Date()
        for _ in 0..<200 { for w in words { _ = clf.decide(w, prev: "KO", final: true) } }
        let perCall = Date().timeIntervalSince(t2) * 1000 / Double(200 * words.count)
        print(String(format: "PROBE\t%@\tbefore=%.1f\tmodel=+%.1f\tpersonal=+%.1f\tload=%.0fms\tpersonal=%.0fms\tdecide=%.3fms",
                     (modelPath as NSString).lastPathComponent, before, afterModel - before, afterPersonal - afterModel, loadMs, personalMs, perCall))
    }
}
