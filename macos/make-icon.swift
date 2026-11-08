// omoji app icon: smiling face inside a magnifier lens on a warm gradient squircle.
import AppKit

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
}

func sparkle(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: x, y: y + r))
    p.addQuadCurve(to: CGPoint(x: x + r, y: y), control: CGPoint(x: x, y: y))
    p.addQuadCurve(to: CGPoint(x: x, y: y - r), control: CGPoint(x: x, y: y))
    p.addQuadCurve(to: CGPoint(x: x - r, y: y), control: CGPoint(x: x, y: y))
    p.addQuadCurve(to: CGPoint(x: x, y: y + r), control: CGPoint(x: x, y: y))
    c.addPath(p)
    c.fillPath()
}

func draw(_ c: CGContext, _ px: Int) {
    let body = CGMutablePath()
    for i in 0..<720 {
        let t = CGFloat(i) / 720 * 2 * .pi, ct = cos(t), st = sin(t)
        let pt = CGPoint(x: 512 + 412 * copysign(pow(abs(ct), 0.4), ct), y: 512 + 412 * copysign(pow(abs(st), 0.4), st))
        i == 0 ? body.move(to: pt) : body.addLine(to: pt)
    }
    body.closeSubpath()

    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: rgb(0x000000, 0.35))
    c.addPath(body)
    c.setFillColor(rgb(0xE8504F))
    c.fillPath()
    c.restoreGState()

    c.saveGState()
    c.addPath(body)
    c.clip()
    c.drawLinearGradient(gradient([rgb(0xFFA23A), rgb(0xF5603F), rgb(0xD62E5C)]),
                         start: CGPoint(x: 250, y: 924), end: CGPoint(x: 774, y: 100),
                         options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.drawRadialGradient(gradient([rgb(0xFFFFFF, 0.28), rgb(0xFFFFFF, 0)]),
                         startCenter: CGPoint(x: 330, y: 830), startRadius: 0,
                         endCenter: CGPoint(x: 330, y: 830), endRadius: 520, options: [])
    c.restoreGState()

    let center = CGPoint(x: 476, y: 566), lens: CGFloat = 268
    let handleEnd = CGPoint(x: 784, y: 258)

    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -14), blur: 26, color: rgb(0x6A1030, 0.45))
    c.setLineCap(.round)
    c.setLineWidth(112)
    c.setStrokeColor(rgb(0x4A1838))
    c.move(to: CGPoint(x: center.x + lens * 0.72, y: center.y - lens * 0.72))
    c.addLine(to: handleEnd)
    c.strokePath()
    c.setFillColor(rgb(0xFFF4E2))
    c.fillEllipse(in: CGRect(x: center.x - lens - 46, y: center.y - lens - 46,
                             width: (lens + 46) * 2, height: (lens + 46) * 2))
    c.restoreGState()

    c.saveGState()
    c.addEllipse(in: CGRect(x: center.x - lens, y: center.y - lens, width: lens * 2, height: lens * 2))
    c.clip()
    c.drawRadialGradient(gradient([rgb(0xFFE877), rgb(0xFFC21F), rgb(0xFF9E1B)]),
                         startCenter: CGPoint(x: center.x - 80, y: center.y + 110), startRadius: 0,
                         endCenter: center, endRadius: lens, options: [.drawsAfterEndLocation])
    c.drawRadialGradient(gradient([rgb(0xC0451A, 0), rgb(0xC0451A, 0.35)]),
                         startCenter: center, startRadius: lens * 0.82,
                         endCenter: center, endRadius: lens, options: [])
    c.restoreGState()

    let ink = rgb(0x4A1838)
    c.setFillColor(ink)
    for dx in [-92.0, 92.0] as [CGFloat] {
        c.fillEllipse(in: CGRect(x: center.x + dx - 36, y: center.y + 34, width: 72, height: 96))
    }
    c.setStrokeColor(ink)
    c.setLineWidth(52)
    c.setLineCap(.round)
    c.addArc(center: CGPoint(x: center.x, y: center.y + 20), radius: 150,
             startAngle: .pi * 1.18, endAngle: .pi * 1.82, clockwise: false)
    c.strokePath()

    c.setFillColor(rgb(0xFF7A59, 0.55))
    for dx in [-188.0, 188.0] as [CGFloat] {
        c.fillEllipse(in: CGRect(x: center.x + dx - 40, y: center.y - 20, width: 80, height: 48))
    }

    c.setFillColor(rgb(0xFFFFFF, 0.55))
    c.fillEllipse(in: CGRect(x: center.x - 196, y: center.y + 130, width: 76, height: 48))

    c.setFillColor(rgb(0xFFF8EA))
    sparkle(c, 800, 790, 96)
    if px > 32 {
        sparkle(c, 720, 870, 36)
    }
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
                              ("128x128", 128), ("128x128@2x", 256), ("256x256", 256),
                              ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
for (name, px) in sizes {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        .retagging(with: .sRGB)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    draw(ctx, px)
    try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("icon_\(name).png"))
}
