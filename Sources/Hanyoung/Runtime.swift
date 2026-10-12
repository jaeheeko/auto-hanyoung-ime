import Foundation
import Engine

/// 앱별 설정. ~/Library/Application Support/Hanyoung/config.json 으로 덮어쓸 수 있다.
struct Config {
    /// 번들 ID → 라벨 가중치(log). 터미널·에디터는 영어 쪽.
    var appBias: [String: [Label: Double]] = [
        "com.apple.Terminal": [.en: 3.0],
        "com.googlecode.iterm2": [.en: 3.0],
        "dev.warp.Warp-Stable": [.en: 3.0],
        "com.github.wez.wezterm": [.en: 3.0],
        "net.kovidgoyal.kitty": [.en: 3.0],
        "com.mitchellh.ghostty": [.en: 3.0],
        "com.microsoft.VSCode": [.en: 1.5],
        "com.todesktop.230313mzl4w4u92": [.en: 1.5],  // Cursor
        "com.apple.dt.Xcode": [.en: 1.5],
        "com.jetbrains.intellij": [.en: 1.5],
        "com.tinyspeck.slackmacgap": [.ko: 0.5],
        "md.obsidian": [.ko: 0.5],
        "com.kakao.KakaoTalkMac": [.ko: 1.0],
    ]
    /// 자동 판정을 끄고 영어로만 입력하는 앱
    var disabledApps: Set<String> = []
    /// 표시 중인 가설을 바꾸려면 다른 가설이 이만큼(log) 더 좋아야 한다
    var hysteresis = 1.1
    /// 되돌리기 키 (54 = 오른쪽 ⌘, 61 = 오른쪽 ⌥)
    var toggleKeyCode: UInt16 = 54
    /// 사용자 사전 1회 학습당 가중치, 최대 횟수
    var userDictWeight = 3.0
    var userDictMaxCount = 3

    static func load(from url: URL) -> Config {
        var c = Config()
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return c }
        if let apps = json["appBias"] as? [String: [String: Any]] {
            for (bundle, dist) in apps {
                var d: [Label: Double] = [:]
                for (l, v) in dist { if let label = Label(rawValue: l), let n = (v as? NSNumber)?.doubleValue { d[label] = n } }
                c.appBias[bundle] = d
            }
        }
        if let disabled = json["disabledApps"] as? [String] { c.disabledApps = Set(disabled) }
        if let h = (json["hysteresis"] as? NSNumber)?.doubleValue { c.hysteresis = h }
        if let k = (json["toggleKeyCode"] as? NSNumber)?.uint16Value { c.toggleKeyCode = k }
        return c
    }
}

/// 되돌리기로 학습한 (키 문자열 → 라벨 → 횟수). JSON으로 저장.
final class UserDict {
    private var entries: [String: [String: Int]] = [:]
    private let url: URL

    init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Int]] {
            entries = json
        }
    }

    func bias(for keys: String, weight: Double, maxCount: Int) -> [Label: Double] {
        guard let e = entries[keys] else { return [:] }
        var d: [Label: Double] = [:]
        for (l, c) in e { if let label = Label(rawValue: l) { d[label] = Double(min(c, maxCount)) * weight } }
        return d
    }

    func learn(_ keys: String, _ label: Label) {
        var e = entries[keys] ?? [:]
        e[label.rawValue, default: 0] += 1
        // 반대 라벨로 학습된 기록은 상쇄한다
        for other in Label.allCases where other != label {
            if let c = e[other.rawValue], c > 0 { e[other.rawValue] = c - 1 }
        }
        entries[keys] = e
        if let data = try? JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

final class Runtime {
    static let shared = Runtime()

    private(set) var classifier: Classifier!
    private(set) var config = Config()
    private(set) var userDict: UserDict!
    let supportDir: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        supportDir = base.appendingPathComponent("Hanyoung", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    }

    func load() {
        config = Config.load(from: supportDir.appendingPathComponent("config.json"))
        userDict = UserDict(url: supportDir.appendingPathComponent("user_dict.json"))
        guard let url = Bundle.main.url(forResource: "hanyoung", withExtension: "json") else {
            fatalError("Resources/hanyoung.json이 없다")
        }
        let t0 = Date()
        do {
            classifier = try Model.load(url: url)
        } catch {
            fatalError("모델 로드 실패: \(error)")
        }
        log(["event": "model_loaded", "ms": Int(Date().timeIntervalSince(t0) * 1000)])
    }

    /// 로컬 JSONL 로그. 비밀번호란에서는 입력기 자체가 호출되지 않는다.
    func log(_ fields: [String: Any]) {
        var entry = fields
        entry["ts"] = ISO8601DateFormatter().string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: entry),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        let url = supportDir.appendingPathComponent("log.jsonl")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? line.data(using: .utf8)!.write(to: url)
        }
    }
}
