import AppKit

let root = CommandLine.arguments[1]
let iconset = root + "/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

func color(_ value: Int) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
}
func rounded(_ rect: NSRect, _ radius: CGFloat, _ fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}
func image(size: Int) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(size) / 1024)
    transform.concat()
    let base = NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 194, yRadius: 194)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSGradient(starting: color(0xE7E9DA), ending: color(0xBEC8B0))!.draw(in: base, angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shadow.shadowBlurRadius = 23
    shadow.shadowOffset = NSSize(width: 0, height: -19)
    shadow.set()
    rounded(NSRect(x: 213, y: 417, width: 598, height: 306), 64, color(0xDADBCF))
    NSGraphicsContext.restoreGraphicsState()
    let lid = NSBezierPath(roundedRect: NSRect(x: 196, y: 491, width: 632, height: 270), xRadius: 58, yRadius: 58)
    NSGradient(starting: color(0xE5E5D8), ending: color(0xFAF8ED))!.draw(in: lid, angle: 90)
    color(0xFFFFFF).withAlphaComponent(0.8).setStroke()
    lid.lineWidth = 3
    lid.stroke()
    rounded(NSRect(x: 288, y: 438, width: 448, height: 28), 9, color(0x3A4034))
    rounded(NSRect(x: 316, y: 634, width: 123, height: 11), 5, color(0x919B82))
    rounded(NSRect(x: 316, y: 610, width: 83, height: 6), 3, color(0xB5BAA9))
    rounded(NSRect(x: 693, y: 622, width: 49, height: 29), 13, color(0xD3D7C6))
    rounded(NSRect(x: 711, y: 686, width: 10, height: 10), 5, color(0x86A76D))
    let paper = NSBezierPath()
    paper.move(to: NSPoint(x: 319, y: 450))
    paper.line(to: NSPoint(x: 705, y: 450))
    paper.line(to: NSPoint(x: 705, y: 242))
    for index in 0..<22 {
        paper.line(to: NSPoint(x: 705 - CGFloat(index) * 17.55 - 8.78, y: 233))
        paper.line(to: NSPoint(x: 705 - CGFloat(index + 1) * 17.55, y: 242))
    }
    paper.close()
    NSGraphicsContext.saveGraphicsState()
    shadow.shadowBlurRadius = 12
    shadow.shadowOffset = NSSize(width: 0, height: -9)
    shadow.set()
    color(0xFCFAEE).setFill()
    paper.fill()
    NSGraphicsContext.restoreGraphicsState()
    for index in 0..<3 {
        let y = CGFloat(390 - index * 51)
        let box = NSBezierPath(roundedRect: NSRect(x: 357, y: y, width: 17, height: 17), xRadius: 2, yRadius: 2)
        color(0x818A73).setStroke(); box.lineWidth = 3; box.stroke()
        rounded(NSRect(x: 396, y: y + 6, width: index == 1 ? 182 : 235, height: 6), 2, color(0xADB29D))
    }
    let mark = NSBezierPath()
    mark.move(to: NSPoint(x: 390, y: 345)); mark.line(to: NSPoint(x: 596, y: 354))
    color(0x55634A).setStroke(); mark.lineWidth = 11; mark.lineCapStyle = .round; mark.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

for pointSize in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let bitmap = image(size: pointSize * scale)
        let name = "icon_\(pointSize)x\(pointSize)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: iconset + "/" + name))
    }
}
