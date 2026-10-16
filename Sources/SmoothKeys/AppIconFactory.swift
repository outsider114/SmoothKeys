import AppKit

enum AppIconFactory {
    static func menuBarImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.black.setFill()
        NSColor.black.setStroke()

        let body = NSBezierPath(roundedRect: NSRect(x: 2, y: 3, width: 14, height: 12), xRadius: 3, yRadius: 3)
        body.lineWidth = 1.8
        body.stroke()

        let keys: [NSRect] = [
            NSRect(x: 5, y: 10, width: 2, height: 2),
            NSRect(x: 8, y: 10, width: 2, height: 2),
            NSRect(x: 11, y: 10, width: 2, height: 2),
            NSRect(x: 5, y: 7, width: 8, height: 1.8)
        ]
        for rect in keys {
            NSBezierPath(roundedRect: rect, xRadius: 0.8, yRadius: 0.8).fill()
        }

        let arc = NSBezierPath()
        arc.move(to: NSPoint(x: 4.2, y: 4.8))
        arc.curve(to: NSPoint(x: 13.8, y: 4.8), controlPoint1: NSPoint(x: 6.5, y: 2.7), controlPoint2: NSPoint(x: 11.5, y: 2.7))
        arc.lineWidth = 1.6
        arc.stroke()

        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "SmoothKeys"
        return image
    }
}
