import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("Resources/SmoothKeys.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let outputs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in outputs {
    let image = renderIcon(size: size)
    let url = iconset.appendingPathComponent(name)
    try writePNG(image: image, to: url)
}

func renderIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill()

    let scale = CGFloat(size) / 1024.0
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale)
    }

    let background = NSBezierPath(roundedRect: r(88, 88, 848, 848), xRadius: 190 * scale, yRadius: 190 * scale)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 42 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -18 * scale)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.set()
    NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.14, alpha: 1).setFill()
    background.fill()
    NSGraphicsContext.restoreGraphicsState()

    let glow = NSGradient(colors: [
        NSColor(calibratedRed: 0.16, green: 0.62, blue: 0.95, alpha: 1),
        NSColor(calibratedRed: 0.42, green: 0.88, blue: 0.70, alpha: 1)
    ])
    glow?.draw(in: background, angle: 35)

    let overlay = NSBezierPath(roundedRect: r(144, 140, 736, 744), xRadius: 150 * scale, yRadius: 150 * scale)
    NSColor(calibratedRed: 0.06, green: 0.08, blue: 0.12, alpha: 0.78).setFill()
    overlay.fill()

    let keyboard = NSBezierPath(roundedRect: r(218, 332, 588, 360), xRadius: 72 * scale, yRadius: 72 * scale)
    keyboard.lineWidth = 30 * scale
    NSColor.white.withAlphaComponent(0.94).setStroke()
    keyboard.stroke()

    NSColor.white.withAlphaComponent(0.96).setFill()
    let keyRects = [
        r(306, 552, 74, 62), r(424, 552, 74, 62), r(542, 552, 74, 62), r(660, 552, 74, 62),
        r(306, 448, 74, 62), r(424, 448, 74, 62), r(542, 448, 74, 62), r(660, 448, 74, 62),
        r(352, 356, 320, 54)
    ]
    for rect in keyRects {
        NSBezierPath(roundedRect: rect, xRadius: 18 * scale, yRadius: 18 * scale).fill()
    }

    let arc = NSBezierPath()
    arc.move(to: NSPoint(x: 292 * scale, y: 282 * scale))
    arc.curve(
        to: NSPoint(x: 732 * scale, y: 282 * scale),
        controlPoint1: NSPoint(x: 396 * scale, y: 164 * scale),
        controlPoint2: NSPoint(x: 628 * scale, y: 164 * scale)
    )
    arc.lineWidth = 34 * scale
    arc.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.92).setStroke()
    arc.stroke()

    let dot = NSBezierPath(ovalIn: r(482, 218, 60, 60))
    NSColor.white.withAlphaComponent(0.96).setFill()
    dot.fill()

    image.unlockFocus()
    return image
}

func writePNG(image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "SmoothKeysIcon", code: 1)
    }
    try png.write(to: url)
}
