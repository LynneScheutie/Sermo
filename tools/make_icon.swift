import AppKit
import Foundation

// 把 icon-source.svg 的图形用 Core Graphics 重画一遍并输出 iconset。
// 之所以不用 SVG 光栅化工具：本机没有 rsvg/cairosvg，Quick Look 也不吃 SVG。
// 坐标沿用 SVG 的写法（左上原点、y 向下），绘制时统一翻转。

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./AppIcon.iconset")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let S: CGFloat = 1024
func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: S - y) }

func draw(in ctx: CGContext) {
    // 背景圆角矩形
    let rect = CGRect(x: 0, y: 0, width: S, height: S)
    let path = CGPath(roundedRect: rect, cornerWidth: 228, cornerHeight: 228, transform: nil)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        CGColor(colorSpace: space, components: [0.165, 0.196, 0.271, 1])!,
        CGColor(colorSpace: space, components: [0.102, 0.125, 0.188, 1])!,
    ] as CFArray
    if let g = CGGradient(colorsSpace: space, colors: bgColors, locations: [0, 1]) {
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])
    }
    ctx.restoreGState()

    let ink = CGColor(colorSpace: space, components: [0.972, 0.949, 0.898, 1])!

    // 图形整体略微放大并下移，让视觉重心落在方形中央（原坐标偏上，底部留白过多）
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 512)
    ctx.scaleBy(x: 1.04, y: 1.04)
    ctx.translateBy(x: -512, y: -512)
    ctx.translateBy(x: 0, y: -24)

    // 触手：七条粗圆头曲线
    let tentacles: [[CGPoint]] = [
        [pt(604, 540), pt(648, 600), pt(704, 620), pt(766, 610)],
        [pt(420, 540), pt(376, 600), pt(320, 620), pt(258, 610)],
        [pt(572, 556), pt(606, 626), pt(662, 664), pt(730, 674)],
        [pt(452, 556), pt(418, 626), pt(362, 664), pt(294, 674)],
        [pt(540, 566), pt(556, 646), pt(596, 700), pt(656, 726)],
        [pt(484, 566), pt(468, 646), pt(428, 700), pt(368, 726)],
        [pt(512, 572), pt(512, 656), pt(500, 712), pt(484, 748)],
    ]
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(44)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    for t in tentacles {
        let p = CGMutablePath()
        p.move(to: t[0])
        p.addCurve(to: t[3], control1: t[1], control2: t[2])
        ctx.addPath(p)
        ctx.strokePath()
    }

    // 头
    let head = CGMutablePath()
    head.move(to: pt(296, 432))
    head.addCurve(to: pt(512, 208), control1: pt(296, 288), control2: pt(392, 208))
    head.addCurve(to: pt(728, 432), control1: pt(632, 208), control2: pt(728, 288))
    head.addCurve(to: pt(652, 586), control1: pt(728, 512), control2: pt(700, 560))
    head.addLine(to: pt(372, 586))
    head.addCurve(to: pt(296, 432), control1: pt(324, 560), control2: pt(296, 512))
    head.closeSubpath()
    ctx.addPath(head)
    ctx.setFillColor(ink)
    ctx.fillPath()

    // 眼睛与嘴
    let dark = CGColor(colorSpace: space, components: [0.118, 0.141, 0.196, 1])!
    ctx.setFillColor(dark)
    for cx in [458, 566] as [CGFloat] {
        let c = pt(cx, 424)
        ctx.fillEllipse(in: CGRect(x: c.x - 21, y: c.y - 21, width: 42, height: 42))
    }
    let smile = CGMutablePath()
    smile.move(to: pt(488, 486))
    smile.addCurve(to: pt(536, 486), control1: pt(500, 500), control2: pt(524, 500))
    ctx.addPath(smile)
    ctx.setStrokeColor(dark)
    ctx.setLineWidth(14)
    ctx.setLineCap(.round)
    ctx.strokePath()

    ctx.restoreGState()   // 结束"整体放大下移"那次变换
}

func write(size: Int, name: String) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = g
    let ctx = g.cgContext
    ctx.scaleBy(x: CGFloat(size) / S, y: CGFloat(size) / S)
    draw(in: ctx)
    g.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: outDir.appendingPathComponent(name))
    print("  \(name)  \(size)×\(size)")
}

print("生成 iconset:")
for base in [16, 32, 128, 256, 512] {
    write(size: base, name: "icon_\(base)x\(base).png")
    write(size: base * 2, name: "icon_\(base)x\(base)@2x.png")
}
