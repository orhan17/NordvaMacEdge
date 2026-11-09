// Renders the app icon. Run from the repo root: swift scripts/make-icon.swift
// Writes Resources/AppIcon.icns and docs/icon.png.
import AppKit

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
}

func context(_ side: Int) -> CGContext {
    CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

func drawIcon() -> CGImage {
    let ctx = context(1024)
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0, 0, 0, 0.35))
    ctx.addPath(bodyPath)
    ctx.setFillColor(color(0.1, 0.1, 0.25))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([color(0.27, 0.29, 0.70), color(0.10, 0.11, 0.30)]),
        start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: []
    )
    ctx.drawLinearGradient(
        gradient([color(1, 1, 1, 0.10), color(1, 1, 1, 0)]),
        start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: []
    )
    ctx.restoreGState()

    let pad = CGRect(x: 212, y: 322, width: 600, height: 380)
    let padPath = CGPath(roundedRect: pad, cornerWidth: 58, cornerHeight: 58, transform: nil)
    ctx.addPath(padPath)
    ctx.setFillColor(color(1, 1, 1, 0.10))
    ctx.fillPath()
    ctx.addPath(padPath)
    ctx.setStrokeColor(color(1, 1, 1, 0.30))
    ctx.setLineWidth(6)
    ctx.strokePath()

    func bar(x: CGFloat, level: CGFloat, colors: [CGColor]) {
        let track = CGRect(x: x, y: pad.midY - 125, width: 38, height: 250)
        ctx.addPath(CGPath(roundedRect: track, cornerWidth: 19, cornerHeight: 19, transform: nil))
        ctx.setFillColor(color(1, 1, 1, 0.14))
        ctx.fillPath()

        let fill = CGRect(x: track.minX, y: track.minY, width: track.width, height: track.height * level)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: fill, cornerWidth: 19, cornerHeight: 19, transform: nil))
        ctx.clip()
        ctx.drawLinearGradient(
            gradient(colors),
            start: CGPoint(x: fill.midX, y: fill.minY), end: CGPoint(x: fill.midX, y: fill.maxY), options: []
        )
        ctx.restoreGState()

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: color(0, 0, 0, 0.35))
        ctx.setFillColor(color(1, 1, 1))
        ctx.fillEllipse(in: CGRect(x: track.midX - 29, y: fill.maxY - 29, width: 58, height: 58))
        ctx.restoreGState()
    }

    bar(x: pad.minX + 52, level: 0.6, colors: [color(1.0, 0.50, 0.22), color(1.0, 0.80, 0.32)])
    bar(x: pad.maxX - 52 - 38, level: 0.78, colors: [color(0.22, 0.52, 1.0), color(0.32, 0.90, 1.0)])

    let strip = CGRect(x: 512 - 105, y: pad.minY + 34, width: 210, height: 18)
    ctx.addPath(CGPath(roundedRect: strip, cornerWidth: 9, cornerHeight: 9, transform: nil))
    ctx.setFillColor(color(1, 1, 1, 0.45))
    ctx.fillPath()

    return ctx.makeImage()!
}

func scaled(_ image: CGImage, to side: Int) -> CGImage {
    let ctx = context(side)
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try data.write(to: url)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let icon = drawIcon()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try writePNG(scaled(icon, to: base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try writePNG(scaled(icon, to: base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()

try FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)
try writePNG(scaled(icon, to: 256), to: root.appendingPathComponent("docs/icon.png"))
print(iconutil.terminationStatus == 0 ? "wrote Resources/AppIcon.icns and docs/icon.png" : "iconutil failed")
