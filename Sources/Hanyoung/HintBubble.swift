import Cocoa
import InputMethodKit
import Engine

/// 되돌리기 키를 쳐서 다음에 올 글자의 언어가 정해졌을 때 커서 옆에 잠깐 보여 주는 말풍선.
/// 힌트는 다음 글자를 치기 전까지 화면에 아무 흔적이 없어서, 걸렸는지 알 길이 없었다.
final class HintBubble {
    static let shared = HintBubble()

    private let panel: NSPanel
    private let label: NSTextField
    private var hideWork: DispatchWorkItem?

    private init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 28, height: 24),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let box = NSVisualEffectView(frame: panel.contentView!.bounds)
        box.material = .hudWindow
        box.state = .active
        box.wantsLayer = true
        box.layer?.cornerRadius = 6
        box.layer?.masksToBounds = true
        box.autoresizingMask = [.width, .height]

        label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.alignment = .center
        label.textColor = .labelColor
        label.frame = box.bounds
        label.autoresizingMask = [.width, .height]
        box.addSubview(label)
        panel.contentView = box
    }

    /// `allowed`가 가리키는 언어를 캐럿 옆에 보여 준다. 영어(혼합 포함)는 A, 한국어는 한.
    func show(_ allowed: Set<Label>, near client: IMKTextInput) {
        label.stringValue = allowed.contains(.ko) && !allowed.contains(.en) ? "한" : "A"
        let caret = Self.caretRect(client)
        // 캐럿 오른쪽 아래. 글줄을 가리지 않는다.
        var origin = NSPoint(x: caret.maxX + 2, y: caret.minY - panel.frame.height - 3)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(origin) }) ?? NSScreen.main {
            origin.x = min(origin.x, screen.visibleFrame.maxX - panel.frame.width - 4)
            origin.y = max(origin.y, screen.visibleFrame.minY + 4)
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        panel.orderOut(nil)
    }

    /// 캐럿의 화면 좌표. 앱이 알려 주지 않으면 마우스 위치 근처.
    private static func caretRect(_ client: IMKTextInput) -> NSRect {
        let sel = client.selectedRange()
        let index = sel.location == NSNotFound ? 0 : sel.location
        var rect = client.firstRect(forCharacterRange: NSRange(location: index, length: 0), actualRange: nil)
        if !usable(rect) {
            rect = .zero
            _ = client.attributes(forCharacterIndex: index, lineHeightRectangle: &rect)
        }
        if !usable(rect) {
            let m = NSEvent.mouseLocation
            return NSRect(x: m.x, y: m.y - 20, width: 0, height: 18)
        }
        return rect
    }

    private static func usable(_ r: NSRect) -> Bool {
        r.origin != .zero || r.size != .zero
    }
}
