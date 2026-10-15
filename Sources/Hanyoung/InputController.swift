import Cocoa
import InputMethodKit
import Engine

/// 되돌리기(한/영) 키의 뜻은 상황에 따라 다르다. 한/영 키를 언어가 바뀌는 자리마다 누르던 습관과 충돌하지 않게 한다.
///   어절 중간에서 한 번     → 여기서 언어가 바뀐다. 앞부분은 보이는 대로 고정, 뒤는 반대 언어
///   어절 사이(빈 상태) 한 번 → 다음 어절은 반대 언어로 시작한다 (화면 변화 없음)
///   빈 상태에서 두 번 연타  → 커서 앞(또는 커서가 닿은) 어절을 다음 가설로
///   선택 영역이 있을 때     → 선택한 글자를 반대 언어로
@objc(HanyoungInputController)
public final class HanyoungInputController: IMKInputController {
    /// 어절 중간에서 가른 앞부분. 글자는 가른 시점에 보이던 대로 고정된다.
    private struct Segment { let keys: String; let text: String; let label: Label }

    private var buffer: [Character] = []          // 조합 중인 현재 구간의 키 (대소문자 유지)
    private var fixed: [Segment] = []             // 앞서 가른 구간들
    private var displayed: Label? = nil           // 현재 구간을 marked text로 보여 주는 가설
    private var forced: Set<Label>? = nil         // 현재 구간에 허용된 가설 (되돌리기 키·힌트로 제한)
    private var forcedByHint = false              // forced가 어절 사이 한 번 톡(힌트)에서 왔는지. 습관 누름일 수 있어 학습하지 않는다
    private var pendingAllowed: Set<Label>? = nil // 빈 상태에서 톡: 다음 어절이 시작할 언어
    private var prevLabel: Label? = nil           // 직전 어절 라벨 (문맥 사전확률)
    private var lastTail: Label = .ko             // 마지막 어절이 끝난 언어. 한/영 힌트의 기준
    private var lastCommit: (text: String, keys: String, label: Label)? = nil
    private var lastTap: Date? = nil              // 되돌리기 키 연타 판정
    private var toggleDown = false                // 조합키형 되돌리기 키가 눌린 상태
    private var otherKeyDuringToggle = false

    private static let doubleTapInterval: TimeInterval = 0.45
    private static let lookAround = 40            // 커서 주변 어절을 찾을 때 읽는 글자 수

    private var runtime: Runtime { Runtime.shared }
    private var notFound: NSRange { NSRange(location: NSNotFound, length: NSNotFound) }

    public override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.union(.flagsChanged).rawValue)
    }

    // MARK: - 이벤트

    public override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event, let client = sender as? IMKTextInput else { return false }
        let bundle = client.bundleIdentifier() ?? ""
        if runtime.config.disabledApps.contains(bundle) { return false }

        switch event.type {
        case .flagsChanged:
            return handleFlags(event, client)
        case .keyDown:
            return handleKey(event, client)
        default:
            return false
        }
    }

    private func handleFlags(_ event: NSEvent, _ client: IMKTextInput) -> Bool {
        guard runtime.config.toggleKeyCodes.contains(event.keyCode) else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let pressed = flags.contains(.command) || flags.contains(.option)
        if pressed {
            toggleDown = true
            otherKeyDuringToggle = false
        } else if toggleDown {
            toggleDown = false
            if !otherKeyDuringToggle { toggle(client) }
        }
        return false
    }

    private func handleKey(_ event: NSEvent, _ client: IMKTextInput) -> Bool {
        if toggleDown { otherKeyDuringToggle = true }
        // 일반 키를 되돌리기 키로 쓰는 경우(예: 오른쪽 ⌘를 F18로 바꿔 한/영 키로 쓰던 설정). 시스템의
        // 입력 소스 전환 단축키가 같은 키에 걸려 있으면 여기까지 오지 않으니 그 단축키는 꺼야 한다.
        if runtime.config.toggleKeyCodes.contains(event.keyCode) {
            toggle(client)
            return true
        }
        lastTap = nil
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            commit(client)
            pendingAllowed = nil
            return false
        }

        switch event.keyCode {
        case 51, 117:  // delete, forward delete
            if !buffer.isEmpty {
                buffer.removeLast()
            } else if let last = fixed.popLast() {
                // 가른 구간 안으로 지워 들어간다: 그 구간을 다시 조합 중으로 되돌린다
                buffer = Array(last.keys)
                forced = [last.label]
                buffer.removeLast()
            } else {
                lastCommit = nil
                pendingAllowed = nil
                return false
            }
            updateMarked(client)
            return true
        case 36, 76:   // return, enter
            commit(client)
            prevLabel = nil
            lastCommit = nil
            pendingAllowed = nil
            return false
        case 48, 53:   // tab, escape
            commit(client)
            lastCommit = nil
            pendingAllowed = nil
            return false
        case 123...126, 115, 119, 116, 121:  // arrows, home, end, page up/down
            commit(client)
            prevLabel = nil
            lastCommit = nil
            pendingAllowed = nil
            return false
        default:
            break
        }

        guard let chars = event.characters, chars.count == 1, let ch = chars.first else {
            commit(client)
            pendingAllowed = nil
            return false
        }
        if Self.isWordChar(ch) {
            if buffer.isEmpty, fixed.isEmpty, let p = pendingAllowed {
                forcedByHint = true
                // 한/영 힌트가 걸려 있으면 새 어절은 그 언어로 시작한다
                forced = p
                pendingAllowed = nil
            }
            buffer.append(ch)
            updateMarked(client)
            return true
        }
        // 공백·숫자·문장부호: 어절 경계. 확정하고 키는 앱에 넘긴다.
        commit(client)
        pendingAllowed = nil
        return false
    }

    private static func isWordChar(_ ch: Character) -> Bool {
        (ch.isLetter && ch.isASCII) || ch == "'"
    }

    // MARK: - 가설 선택

    private func bias(_ client: IMKTextInput, keys: String) -> [Label: Double] {
        var b = runtime.config.appBias[client.bundleIdentifier() ?? ""] ?? [:]
        for (l, v) in runtime.userDict.bias(for: keys, weight: runtime.config.userDictWeight,
                                            maxCount: runtime.config.userDictMaxCount) {
            b[l, default: 0] += v
        }
        return b
    }

    private func decide(_ client: IMKTextInput, keys: String, final: Bool) -> Decision {
        runtime.classifier.decide(keys, prev: prevLabel?.rawValue ?? "BR",
                                  bias: bias(client, keys: keys), final: final)
    }

    /// 허용된 가설 중 가장 좋은 것. 제한이 없으면 1위, 단 표시 중인 가설은 히스테리시스로 지킨다.
    private func pick(_ d: Decision, hysteresis: Bool) -> Label {
        if let f = forced {
            let allowed = f.filter { d.texts[$0] != nil }
            if let best = allowed.max(by: { d.scores[$0]! < d.scores[$1]! }) { return best }
        }
        if hysteresis, let cur = displayed, cur != d.label, let curScore = d.scores[cur], d.texts[cur] != nil,
           d.scores[d.label]! - curScore < runtime.config.hysteresis {
            return cur
        }
        return d.label
    }

    /// 가설을 점수 순으로 돌 때 `after` 다음 것. 1위였다면 2위, 그다음 3위, 다시 1위.
    private static func nextLabel(_ d: Decision, after: Label) -> Label {
        let order = d.texts.keys.sorted { d.scores[$0]! > d.scores[$1]! }
        guard let i = order.firstIndex(of: after) else { return order[0] }
        return order[(i + 1) % order.count]
    }

    /// 이 언어로 끝난 뒤 "반대 언어"로 시작하는 가설들. 영어 뒤는 한국어, 한국어 뒤는 영어 또는 영어+조사.
    private static func startsOpposite(of label: Label) -> Set<Label> {
        switch label {
        case .en: return [.ko]
        case .ko, .mix: return [.en, .mix]
        }
    }

    private static func tail(_ label: Label) -> Label { label == .mix ? .ko : label }

    // MARK: - 조합 표시

    private func updateMarked(_ client: IMKTextInput) {
        let prefix = fixed.map(\.text).joined()
        guard !buffer.isEmpty else {
            displayed = nil
            if prefix.isEmpty {
                client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: notFound)
            } else {
                setMarked(client, prefix)
            }
            return
        }
        let d = decide(client, keys: String(buffer), final: false)
        let label = pick(d, hysteresis: true)
        displayed = label
        setMarked(client, prefix + (d.texts[label] ?? d.text))
    }

    private func setMarked(_ client: IMKTextInput, _ text: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .markedClauseSegment: 0,
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        client.setMarkedText(s, selectionRange: NSRange(location: s.length, length: 0), replacementRange: notFound)
    }

    // MARK: - 확정

    private func commit(_ client: IMKTextInput) {
        guard !buffer.isEmpty || !fixed.isEmpty else { return }
        var segments = fixed
        var model: Label? = nil
        var margin = 0.0
        if !buffer.isEmpty {
            let keys = String(buffer)
            let d = decide(client, keys: keys, final: true)
            let label = pick(d, hysteresis: false)
            segments.append(Segment(keys: keys, text: d.texts[label] ?? d.text, label: label))
            model = d.label
            margin = d.margin
        }
        let text = segments.map(\.text).joined()
        let keys = segments.map(\.keys).joined()
        client.insertText(text, replacementRange: notFound)

        let last = segments.last!.label
        prevLabel = last
        lastTail = Self.tail(last)
        if segments.count == 1 {
            lastCommit = (text, keys, last)
            // 되돌리기·가르기 취소로 모델과 다른 결과가 됐으면 사용자가 결과를 보고 고친 것이니 학습한다.
            // 어절 사이 한 번 톡(힌트)은 옛 습관으로 누른 것일 수 있어(menubar→ㅡ두ㅕㅠㅁㄱ) 학습하지 않는다.
            if forced != nil, !forcedByHint, let m = model, m != last { runtime.learn(keys, last) }
        } else {
            lastCommit = nil
            // 영어|한국어로 가른 어절은 혼합 어절로 학습한다
            if segments.count == 2, segments[0].label == .en, segments[1].label == .ko {
                runtime.learn(keys, .mix, split: segments[0].keys.count)
            }
        }
        runtime.log(["event": "commit", "app": client.bundleIdentifier() ?? "", "keys": keys,
                     "label": segments.map(\.label.rawValue).joined(separator: "+"), "text": text,
                     "forced": forced != nil || segments.count > 1, "model": model?.rawValue ?? "",
                     "margin": (margin * 10).rounded() / 10])
        buffer = []
        fixed = []
        displayed = nil
        forced = nil
        forcedByHint = false
    }

    public override func commitComposition(_ sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }
        commit(client)
    }

    public override func deactivateServer(_ sender: Any!) {
        if let client = sender as? IMKTextInput { commit(client) }
        prevLabel = nil
        lastCommit = nil
        pendingAllowed = nil
    }

    // MARK: - 되돌리기 키

    private func toggle(_ client: IMKTextInput) {
        let now = Date()
        let quick = lastTap.map { now.timeIntervalSince($0) < Self.doubleTapInterval } ?? false
        lastTap = now

        if !buffer.isEmpty {
            // 어절 중간: 여기서 언어가 바뀐다. 앞부분은 보이는 대로 고정하고 뒤는 반대 언어로.
            let keys = String(buffer)
            let d = decide(client, keys: keys, final: false)
            let label = displayed ?? pick(d, hysteresis: false)
            fixed.append(Segment(keys: keys, text: d.texts[label] ?? d.text, label: label))
            buffer = []
            displayed = nil
            forced = Self.startsOpposite(of: label)
            updateMarked(client)
            return
        }
        if !fixed.isEmpty {
            // 가른 직후 다시 톡: 가르기를 취소하고 어절 전체를 다음 가설로
            let keys = fixed.map(\.keys).joined()
            let from = fixed.first!.label
            fixed = []
            buffer = Array(keys)
            let d = decide(client, keys: keys, final: false)
            forced = [Self.nextLabel(d, after: from)]
            updateMarked(client)
            return
        }

        // 조합 중이 아닐 때
        let sel = client.selectedRange()
        if sel.location != NSNotFound, sel.length > 0 {
            pendingAllowed = nil
            convert(client, range: sel)
            return
        }
        if quick {
            // 두 번 톡: 커서 앞(또는 커서가 닿은) 어절을 다음 가설로
            pendingAllowed = nil
            undoAtCaret(client, caret: sel)
            return
        }
        // 한 번 톡: 다음 어절은 반대 언어로 시작한다 (한/영 키 습관). 화면은 바뀌지 않는다.
        pendingAllowed = Self.startsOpposite(of: lastTail)
        runtime.log(["event": "hint", "app": client.bundleIdentifier() ?? "", "after": lastTail.rawValue])
    }

    private func undoAtCaret(_ client: IMKTextInput, caret sel: NSRange) {
        guard sel.location != NSNotFound, sel.length == 0 else { return }
        if let lc = lastCommit {
            let len = (lc.text as NSString).length
            if sel.location >= len {
                let range = NSRange(location: sel.location - len, length: len)
                if client.attributedSubstring(from: range)?.string == lc.text {
                    cycle(client, range: range, keys: lc.keys, from: lc.label)
                    return
                }
            }
        }
        // 방금 어절이 아니면 커서가 닿은 어절을 찾는다
        if let range = wordRange(client, aroundCaret: sel.location) { convert(client, range: range) }
    }

    /// 확정된 어절을 다음 가설로 바꾼다. 연타하면 계속 돈다.
    private func cycle(_ client: IMKTextInput, range: NSRange, keys: String, from: Label) {
        let d = runtime.classifier.decide(keys, prev: "BR", final: true)
        let newLabel = Self.nextLabel(d, after: from)
        guard let newText = d.texts[newLabel] else { return }
        client.insertText(newText, replacementRange: range)
        lastCommit = (newText, keys, newLabel)
        prevLabel = newLabel
        lastTail = Self.tail(newLabel)
        runtime.learn(keys, newLabel)
        runtime.log(["event": "undo", "app": client.bundleIdentifier() ?? "", "keys": keys,
                     "from": from.rawValue, "to": newLabel.rawValue, "text": newText])
    }

    // MARK: - 확정된 글자 바꾸기 (선택 영역·커서 주변)

    private static func isWordChar(_ u: unichar) -> Bool {
        guard let s = UnicodeScalar(u) else { return false }
        let ch = Character(s)
        return isWordChar(ch) || Hangul.isHangul(ch)
    }

    /// 커서가 닿은 어절(한글·영문·`'`의 연속)의 범위
    private func wordRange(_ client: IMKTextInput, aroundCaret loc: Int) -> NSRange? {
        let docLen = client.length()
        let start = max(0, loc - Self.lookAround)
        let end = docLen == NSNotFound ? loc + Self.lookAround : min(docLen, loc + Self.lookAround)
        guard end > start,
              let around = client.attributedSubstring(from: NSRange(location: start, length: end - start))?.string else {
            return nil
        }
        let s = around as NSString
        var a = min(loc - start, s.length), b = a
        while a > 0, Self.isWordChar(s.character(at: a - 1)) { a -= 1 }
        while b < s.length, Self.isWordChar(s.character(at: b)) { b += 1 }
        guard b > a else { return nil }
        return NSRange(location: start + a, length: b - a)
    }

    /// 범위 안의 글자를 어절마다 반대 언어로 바꾼다. 한글은 키열을 되살려 영어로, 영어는 한글로 조립한다.
    private func convert(_ client: IMKTextInput, range: NSRange) {
        guard let text = client.attributedSubstring(from: range)?.string else { return }
        var out = ""
        var learned: [(keys: String, label: Label, text: String)] = []
        var run = ""
        func flush() {
            guard !run.isEmpty else { return }
            let r = convertToken(run)
            out += r.text
            if let l = r.label { learned.append((r.keys, l, r.text)) }
            run = ""
        }
        for ch in text {
            if Self.isWordChar(ch) || Hangul.isHangul(ch) { run.append(ch) } else { flush(); out.append(ch) }
        }
        flush()
        guard out != text else { return }
        client.insertText(out, replacementRange: range)
        for l in learned { runtime.learn(l.keys, l.label) }
        if learned.count == 1, let l = learned.first, out == l.text {
            // 어절 하나를 바꿨으면 연타로 다음 가설까지 돌 수 있게 기억한다
            lastCommit = (l.text, l.keys, l.label)
            prevLabel = l.label
            lastTail = Self.tail(l.label)
        } else {
            lastCommit = nil
        }
        runtime.log(["event": "convert", "app": client.bundleIdentifier() ?? "", "from": text, "to": out])
    }

    /// 어절 하나를 다음 가설로. 모델 가설 중 지금 글자와 같은 것이 있으면 그 다음 가설, 없으면 문자 종류별로 뒤집는다.
    private func convertToken(_ token: String) -> (text: String, keys: String, label: Label?) {
        let keys = Hangul.toKeys(token)
        let d = runtime.classifier.decide(keys, prev: "BR", final: true)
        if let current = d.texts.first(where: { $0.value == token })?.key {
            let next = Self.nextLabel(d, after: current)
            return (d.texts[next]!, keys, next)
        }
        var out = "", run = "", hangul = false
        func flush() {
            guard !run.isEmpty else { return }
            out += hangul ? Hangul.toKeys(run) : Hangul.compose(run).text
            run = ""
        }
        for ch in token {
            let h = Hangul.isHangul(ch)
            if !run.isEmpty, h != hangul { flush() }
            hangul = h
            run.append(ch)
        }
        flush()
        return (out, keys, nil)
    }
}
