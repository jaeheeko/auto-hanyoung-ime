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
    /// 되돌리기 키. 54 = 오른쪽 ⌘, 61 = 오른쪽 ⌥(조합키는 flagsChanged로 톡 판정),
    /// 79 = F18(hidutil·Karabiner로 오른쪽 ⌘를 한/영 키로 바꿔 쓰는 흔한 설정. 일반 키는 keyDown에서 바로 되돌리기)
    var toggleKeyCodes: Set<UInt16> = [54, 79]
    /// 사용자 사전 1회 학습당 가중치, 최대 횟수
    /// 교정 1회가 어휘 덧층에 더하는 빈도. 영어 사전 총량 46만 기준 20이면 log 확률 약 -10 (흔한 단어 수준).
    static let learnWeight = 20.0
    var userDictWeight = 10.0   // 교정 1회로 격차 10점까지 뒤집힌다. 실사용 오판 격차는 1~17점.
    var userDictMaxCount = 3
    /// 어절을 지우고 같은 키열을 다시 치면 다음 가설로 바꾸는 기능이 발동할 원래 판정 격차 상한. 0이면 끈다.
    /// 로그상 실제 교정 22건 중 14건이 격차 8 미만, 다른 이유의 재입력은 대부분 13 이상.
    var retypeMargin = 10.0

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
        if let r = (json["retypeMargin"] as? NSNumber)?.doubleValue { c.retypeMargin = r }
        if let k = (json["toggleKeyCode"] as? NSNumber)?.uint16Value { c.toggleKeyCodes = [k] }
        if let ks = json["toggleKeyCodes"] as? [NSNumber] { c.toggleKeyCodes = Set(ks.map { $0.uint16Value }) }
        return c
    }
}

/// 되돌리기로 학습한 (키 문자열 → 라벨 → 횟수). JSON으로 저장.
final class UserDict {
    private(set) var entries: [String: [String: Int]] = [:]
    private let url: URL

    init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Int]] {
            entries = json
        }
    }

    func bias(for keys: String, weight: Double, maxCount: Int) -> [Label: Double] {
        var d: [Label: Double] = [:]
        if let e = entries[keys] {
            for (l, c) in e { if let label = Label(rawValue: l) { d[label] = Double(min(c, maxCount)) * weight } }
        }
        // 영어로 배운 단어 뒤에 한글로 조립되는 꼬리가 붙었으면(db→db에서) 영어+조사 가설에 같은 편향을 준다.
        // 어휘 덧층만으로는 `유에서`처럼 진짜 한국어 어절과 겹치는 경우를 못 뒤집는다.
        var best = 0
        for (w, e) in entries where keys.count > w.count && keys.hasPrefix(w) {
            guard let c = e[Label.en.rawValue], c > 0 else { continue }
            let tail = Hangul.compose(String(keys.dropFirst(w.count)))
            if tail.lone == 0 && tail.shiftBad == 0 { best = max(best, c) }
        }
        if best > 0 { d[.mix, default: 0] += Double(min(best, maxCount)) * weight }
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
        guard let url = Bundle.main.url(forResource: "hanyoung", withExtension: "model") else {
            fatalError("Resources/hanyoung.model이 없다")
        }
        let t0 = Date()
        do {
            classifier = try Model.load(url: url)
        } catch {
            fatalError("모델 로드 실패: \(error)")
        }
        log(["event": "model_loaded", "ms": Int(Date().timeIntervalSince(t0) * 1000)])

        // 개인 층: tools/personalize.py가 만든 어휘 사전이 있으면 기본 모델에 더한다
        let lexURL = supportDir.appendingPathComponent("user_lexicon.json")
        if FileManager.default.fileExists(atPath: lexURL.path) {
            do {
                let t1 = Date()
                let personal = try Model.PersonalLexicon.load(url: lexURL)
                classifier.applyPersonal(ko: personal.ko, en: personal.en, suffix: personal.suffix)
                log(["event": "personal_loaded", "ko": personal.ko.count, "en": personal.en.count,
                     "suffix": personal.suffix.count, "ms": Int(Date().timeIntervalSince(t1) * 1000)])
            } catch {
                log(["event": "personal_failed", "error": "\(error)"])
            }
        }
        // 교정 학습 사전을 어휘 덧층에도 되살린다 (조사 변형·대소문자 변형까지 일반화)
        for (keys, counts) in userDict.entries {
            for (l, c) in counts where c > 0 {
                if let label = Label(rawValue: l) {
                    classifier.learn(keys: keys, label: label, weight: Config.learnWeight * Double(min(c, config.userDictMaxCount)))
                }
            }
        }
    }

    /// 사용자가 고친 어절을 학습한다: 키열 사전(판정 편향)과 어휘 덧층(일반화) 둘 다.
    func learn(_ keys: String, _ label: Label, split: Int? = nil) {
        userDict.learn(keys, label)
        classifier.learn(keys: keys, label: label, split: split, weight: Config.learnWeight)
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
