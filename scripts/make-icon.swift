// Draws the app icon and writes all sizes of the macOS icon set.
// Usage: swift scripts/make-icon.swift KimaiTimer/Assets.xcassets/AppIcon.appiconset
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".", isDirectory: true)

func drawIcon(pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    // Everything below is specified on a 1024 point canvas.
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    // macOS icon grid: 824 pt rounded square centred on the canvas, with a soft shadow.
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.3))
    context.addPath(platePath)
    context.setFillColor(CGColor(red: 0.07, green: 0.42, blue: 0.56, alpha: 1))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(platePath)
    context.clip()
    let colors = [
        CGColor(red: 0.16, green: 0.71, blue: 0.66, alpha: 1),
        CGColor(red: 0.07, green: 0.36, blue: 0.62, alpha: 1)
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    context.drawLinearGradient(
        gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    context.restoreGState()

    // Stopwatch: crown, ring, elapsed sector and hand.
    let center = CGPoint(x: 512, y: 480)
    let white = CGColor(gray: 1, alpha: 1)
    context.setFillColor(white)
    context.addPath(CGPath(
        roundedRect: CGRect(x: 462, y: 760, width: 100, height: 64), cornerWidth: 22, cornerHeight: 22,
        transform: nil))
    context.fillPath()
    context.fill(CGRect(x: 490, y: 722, width: 44, height: 50))

    context.setStrokeColor(white)
    context.setLineWidth(58)
    context.addArc(center: center, radius: 232, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.strokePath()

    // Elapsed time: a translucent sector from 12 o'clock to the hand at 4 o'clock.
    let handAngle = CGFloat.pi / 2 - CGFloat.pi * 2 / 3
    context.setFillColor(CGColor(gray: 1, alpha: 0.32))
    context.move(to: center)
    context.addArc(center: center, radius: 170, startAngle: .pi / 2, endAngle: handAngle, clockwise: true)
    context.closePath()
    context.fillPath()

    context.setLineCap(.round)
    context.setLineWidth(44)
    context.move(to: center)
    context.addLine(to: CGPoint(x: center.x + cos(handAngle) * 150, y: center.y + sin(handAngle) * 150))
    context.strokePath()
    context.setFillColor(white)
    context.addArc(center: center, radius: 40, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.fillPath()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

struct IconImage {
    let points: Int
    let scale: Int
    var file: String { "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png" }
}

let images = [16, 32, 128, 256, 512].flatMap { [IconImage(points: $0, scale: 1), IconImage(points: $0, scale: 2)] }
for image in images {
    try drawIcon(pixels: image.points * image.scale).write(to: output.appendingPathComponent(image.file))
}
let entries = images.map {
    #"    { "filename" : "\#($0.file)", "idiom" : "mac", "scale" : "\#($0.scale)x", "size" : "\#($0.points)x\#($0.points)" }"#
}
let contents = """
{
  "images" : [
\(entries.joined(separator: ",\n"))
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

"""
try contents.write(to: output.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote \(images.count) icons to \(output.path)")
