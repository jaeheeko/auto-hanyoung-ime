// 입력 메뉴 아이콘 생성. 사용: swift scripts/make_icon.swift assets/menu.tiff
// 메뉴 막대 아이콘은 16pt 정사각형이고 템플릿(검정 + 알파)으로 그려야 라이트/다크 모드에 맞게 표시된다.
// 글자의 실제 잉크 경계(usesDeviceMetrics)로 중앙을 맞춘다. 줄 높이 기준으로 맞추면 디센더 여백 때문에 아래로 쏠린다.
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets/menu.tiff"
let pointSize: CGFloat = 16
let label = "한A"

func render(scale: CGFloat) -> NSBitmapImageRep {
    let px = Int(pointSize * scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pointSize, height: pointSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.set()
    NSRect(x: 0, y: 0, width: pointSize, height: pointSize).fill()

    // 폭 15pt 안에 들어오는 가장 큰 글자 크기
    var fontSize: CGFloat = 13
    var text = NSAttributedString()
    var ink = NSRect.zero
    while fontSize > 6 {
        text = NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
            .foregroundColor: NSColor.black,
        ])
        ink = text.boundingRect(with: NSSize(width: 1000, height: 1000),
                                options: [.usesLineFragmentOrigin, .usesDeviceMetrics])
        if ink.width <= pointSize - 1 { break }
        fontSize -= 0.5
    }
    // ink는 draw(at:) 원점 기준 잉크 경계. 잉크 중심을 캔버스 중심에 놓는다.
    let origin = NSPoint(x: (pointSize - ink.width) / 2 - ink.minX,
                         y: (pointSize - ink.height) / 2 - ink.minY)
    text.draw(at: origin)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
image.addRepresentation(render(scale: 1))
image.addRepresentation(render(scale: 2))
guard let tiff = image.tiffRepresentation else { fatalError("TIFF 변환 실패") }
try! FileManager.default.createDirectory(atPath: (out as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
try! tiff.write(to: URL(fileURLWithPath: out))
print("wrote \(out): \(Int(pointSize))pt, 1x + 2x")
