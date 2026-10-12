// 입력 메뉴 아이콘 생성. 사용: swift scripts/make_icon.swift assets/menu.png
// 메뉴 막대 아이콘은 템플릿(검정 + 알파)으로 그려야 라이트/다크 모드에 맞게 표시된다.
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets/menu.png"
let size = NSSize(width: 32, height: 32)
let image = NSImage(size: size)
image.lockFocus()
NSColor.clear.set()
NSRect(origin: .zero, size: size).fill()

let frame = NSRect(x: 1, y: 1, width: 30, height: 30)
let path = NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6)
path.lineWidth = 2.5
NSColor.black.setStroke()
path.stroke()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 15, weight: .bold),
    .foregroundColor: NSColor.black,
    .paragraphStyle: paragraph,
]
let text = NSAttributedString(string: "한A", attributes: attrs)
let textSize = text.size()
text.draw(in: NSRect(x: 0, y: (size.height - textSize.height) / 2 - 0.5, width: size.width, height: textSize.height))
image.unlockFocus()

guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("PNG 변환 실패")
}
try! FileManager.default.createDirectory(atPath: (out as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out) \(Int(size.width))x\(Int(size.height))")
