import Cocoa
import InputMethodKit
import Engine

@objc(HanyoungInputController)
public final class HanyoungInputController: IMKInputController {
    private var buffer: [Character] = []          // 조합 중인 키 (대소문자 유지)
    private var displayed: Label? = nil           // 현재 marked text로 보여 주는 가설
    private var forced: Label? = nil              // 되돌리기 키로 고정한 가설
    private var prevLabel: Label? = nil           // 직전 어절 라벨 (문맥 사전확률)
    private var lastCommit: (text: String, keys: String, label: Label)? = nil
    private var toggleDown = false                // 되돌리기 키가 눌린 상태
    private var otherKeyDuringToggle = false

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
        guard event.keyCode == runtime.config.toggleKeyCode else { return false }
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
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            commit(client)
            return false
        }

        switch event.keyCode {
        case 51, 117:  // delete, forward delete
            if buffer.isEmpty {
                lastCommit = nil
                return false
            }
            buffer.removeLast()
            updateMarked(client)
            return true
        case 36, 76:   // return, enter
            commit(client)
            prevLabel = nil
            lastCommit = nil
            return false
        case 48, 53:   // tab, escape
            commit(client)
            lastCommit = nil
            return false
        case 123...126, 115, 119, 116, 121:  // arrows, home, end, page up/down
            commit(client)
            prevLabel = nil
            lastCommit = nil
            return false
        default:
            break
        }

        guard let chars = event.characters, chars.count == 1, let ch = chars.first else {
            commit(client)
            return false
        }
        if (ch.isLetter && ch.isASCII) || ch == "'" {
            buffer.append(ch)
            updateMarked(client)
            return true
        }
        // 공백·숫자·문장부호: 어절 경계. 확정하고 키는 앱에 넘긴다.
        commit(client)
        return false
    }

    // MARK: - 조합 표시

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

    private func updateMarked(_ client: IMKTextInput) {
        guard !buffer.isEmpty else {
            displayed = nil
            client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: notFound)
            return
        }
        let keys = String(buffer)
        let d = decide(client, keys: keys, final: false)
        var label = d.label
        if let f = forced, d.texts[f] != nil {
            label = f
        } else if let cur = displayed, cur != d.label, let curScore = d.scores[cur] {
            // 히스테리시스: 표시 중인 가설을 충분히 이길 때만 바꾼다
            if d.scores[d.label]! - curScore < runtime.config.hysteresis, d.texts[cur] != nil {
                label = cur
            }
        }
        displayed = label
        setMarked(client, d.texts[label] ?? d.text)
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
        guard !buffer.isEmpty else { return }
        let keys = String(buffer)
        let d = decide(client, keys: keys, final: true)
        var label = d.label
        if let f = forced, d.texts[f] != nil { label = f }
        let text = d.texts[label] ?? d.text
        client.insertText(text, replacementRange: notFound)
        lastCommit = (text, keys, label)
        prevLabel = label
        runtime.log(["event": "commit", "app": client.bundleIdentifier() ?? "", "keys": keys,
                     "label": label.rawValue, "text": text, "forced": forced != nil,
                     "margin": (d.margin * 10).rounded() / 10])
        buffer = []
        displayed = nil
        forced = nil
    }

    public override func commitComposition(_ sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }
        commit(client)
    }

    public override func deactivateServer(_ sender: Any!) {
        if let client = sender as? IMKTextInput { commit(client) }
        prevLabel = nil
        lastCommit = nil
    }

    // MARK: - 되돌리기 (토글 키 톡)

    private func toggle(_ client: IMKTextInput) {
        if !buffer.isEmpty {
            // 조합 중: 다음 가설로 고정
            let keys = String(buffer)
            let d = decide(client, keys: keys, final: false)
            let current = forced ?? displayed ?? d.label
            forced = current.next(mixAvailable: d.texts[.mix] != nil)
            updateMarked(client)
            return
        }
        guard let lc = lastCommit else { return }
        // 방금 확정한 어절을 반대 언어로 바꾼다. 커서 바로 앞 텍스트가 그 어절일 때만.
        let sel = client.selectedRange()
        let len = (lc.text as NSString).length
        guard sel.location != NSNotFound, sel.length == 0, sel.location >= len else { return }
        let range = NSRange(location: sel.location - len, length: len)
        if let before = client.attributedSubstring(from: range)?.string, before != lc.text { return }

        let saved = prevLabel
        prevLabel = nil  // 되돌리기 판정은 어절 자체 점수로
        let d = runtime.classifier.decide(lc.keys, prev: "BR", final: true)
        prevLabel = saved
        let newLabel = lc.label.next(mixAvailable: d.texts[.mix] != nil)
        guard let newText = d.texts[newLabel] else { return }
        client.insertText(newText, replacementRange: range)
        lastCommit = (newText, lc.keys, newLabel)
        prevLabel = newLabel
        runtime.userDict.learn(lc.keys, newLabel)
        runtime.log(["event": "undo", "app": client.bundleIdentifier() ?? "", "keys": lc.keys,
                     "from": lc.label.rawValue, "to": newLabel.rawValue, "text": newText])
    }
}
