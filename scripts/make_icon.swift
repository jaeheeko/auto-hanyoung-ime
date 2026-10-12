// 입력 메뉴 아이콘 생성. 사용: swift scripts/make_icon.swift assets
//
// macOS 26(Tahoe)은 입력 소스 아이콘을 시스템이 직접 그린다. Info.plist의 TISIconLabels에 글자(Primary·Secondary)나
// 그림(CustomIcon, 글리프만 있는 PDF)을 주면 시스템이 표준 둥근 박스에 넣고 다크 모드에서 반전한다. 따라서
//   assets/auto.pdf  — 박스 없이 글리프만(검정): "한/A" 한 줄, 중앙. CustomIcon용.
//   assets/menu.tiff — 메뉴 막대용(tsInputModeMenuIconFileKey). macOS 26도 메뉴 막대에는 이 TIFF를 쓴다(CustomIcon은 시스템 설정에만).
//                      꽉 찬 검은 둥근 사각형에 글리프를 뚫은 형태, 1x+2x. 모드 딕셔너리에 TISIconIsTemplate를 줘야 반투명·반전된다.
import AppKit
import CoreText

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets"
let lines = ["한/A"]

/// 글자 한 줄을 폭 width에 맞춘 CTLine과 글리프 잉크 경계(기준선 원점 기준)
func fit(_ text: String, width: CGFloat) -> (line: CTLine, ink: CGRect) {
    var size: CGFloat = 60
    while size > 2 {
        let font = NSFont.systemFont(ofSize: size, weight: .heavy)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black]))
        let ink = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        if ink.width <= width { return (line, ink) }
        size -= 0.25
    }
    fatalError("글자를 맞출 수 없다")
}

/// 두 줄 글리프를 (origin에서 시작하는) width × height 영역에 그린다. 반환: 잉크 전체 높이.
func drawGlyph(_ cg: CGContext, origin: CGPoint, width: CGFloat) -> CGFloat {
    let fitted = lines.map { fit($0, width: width) }
    let gap = width * 0.08
    let height = fitted.map(\.ink.height).reduce(0, +) + gap * CGFloat(lines.count - 1)
    var y = origin.y + height
    for f in fitted {
        y -= f.ink.height
        let x = origin.x + (width - f.ink.width) / 2
        cg.textPosition = CGPoint(x: x - f.ink.minX, y: y - f.ink.minY)
        CTLineDraw(f.line, cg)
        y -= gap
    }
    return height
}

func glyphHeight(width: CGFloat) -> CGFloat {
    let fitted = lines.map { fit($0, width: width) }
    return fitted.map(\.ink.height).reduce(0, +) + width * 0.08 * CGFloat(lines.count - 1)
}

// 1) CustomIcon PDF: 글리프만, 캔버스를 꽉 채운다 (Apple AinuIM의 Ainu@2x.pdf와 같은 방식)
let pdfWidth: CGFloat = 36
let pdfHeight = glyphHeight(width: pdfWidth).rounded(.up)
let pdfURL = URL(fileURLWithPath: "\(outDir)/auto.pdf")
var box = CGRect(x: 0, y: 0, width: pdfWidth, height: pdfHeight)
let pdf = CGContext(pdfURL as CFURL, mediaBox: &box, nil)!
pdf.beginPDFPage(nil)
let h = glyphHeight(width: pdfWidth)
_ = drawGlyph(pdf, origin: CGPoint(x: 0, y: (pdfHeight - h) / 2), width: pdfWidth)
pdf.endPDFPage()
pdf.closePDF()
print("wrote \(pdfURL.path): \(Int(pdfWidth))x\(Int(pdfHeight))pt 글리프")

// 2) 메뉴 막대용 TIFF: 검은 둥근 사각형에 글리프를 뚫음, 1x + 2x. 메뉴 막대는 이 파일을 점 크기 그대로 그리고,
//    모드 딕셔너리의 TISIconIsTemplate가 참이면 시스템 라벨 박스(ABC의 "A")와 같은 반투명·다크 모드 반전 스타일로 그린다.
//    크기는 macOS 26의 ABC 라벨 박스를 잰 값(약 21.5×16pt, 모서리 4pt)에 맞춘다.
let boxWidth: CGFloat = 22, boxHeight: CGFloat = 16
func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(boxWidth * scale), pixelsHigh: Int(boxHeight * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: boxWidth, height: boxHeight)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    cg.clear(CGRect(x: 0, y: 0, width: boxWidth, height: boxHeight))
    cg.setFillColor(.black)
    cg.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: boxWidth, height: boxHeight), cornerWidth: 4, cornerHeight: 4, transform: nil))
    cg.fillPath()
    let w = boxWidth - 4
    let gh = glyphHeight(width: w)
    cg.setBlendMode(.destinationOut)
    _ = drawGlyph(cg, origin: CGPoint(x: (boxWidth - w) / 2, y: (boxHeight - gh) / 2), width: w)
    cg.setBlendMode(.normal)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}
let image = NSImage(size: NSSize(width: boxWidth, height: boxHeight))
image.addRepresentation(render(scale: 1))
image.addRepresentation(render(scale: 2))
let tiffURL = URL(fileURLWithPath: "\(outDir)/menu.tiff")
try! image.tiffRepresentation!.write(to: tiffURL)
print("wrote \(tiffURL.path): \(Int(boxWidth))x\(Int(boxHeight))pt 1x+2x")
