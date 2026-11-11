import AppKit
import Foundation

func createIconImage(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let context = NSGraphicsContext.current?.cgContext
    context?.saveGState()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)

    // Inset for standard macOS squircle shape padding
    let inset = size * 0.08
    let iconRect = rect.insetBy(dx: inset, dy: inset)
    let cornerRadius = size * 0.22

    // Background squircle path
    let squirclePath = NSBezierPath(roundedRect: iconRect, xRadius: cornerRadius, yRadius: cornerRadius)

    // Dark sleek gradient background
    let bgGradient = NSGradient(
        colors: [
            NSColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1.0),
            NSColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1.0)
        ]
    )
    bgGradient?.draw(in: squirclePath, angle: -45)

    // Subtle 1px translucent inner highlight border
    NSColor(white: 1.0, alpha: 0.12).setStroke()
    squirclePath.lineWidth = max(1.0, size * 0.015)
    squirclePath.stroke()

    // Draw central hardware chip / gauge background
    let chipInset = size * 0.22
    let chipRect = rect.insetBy(dx: chipInset, dy: chipInset)
    let chipCorner = size * 0.08
    let chipPath = NSBezierPath(roundedRect: chipRect, xRadius: chipCorner, yRadius: chipCorner)

    let chipGradient = NSGradient(
        colors: [
            NSColor(red: 0.15, green: 0.18, blue: 0.24, alpha: 0.9),
            NSColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 0.9)
        ]
    )
    chipGradient?.draw(in: chipPath, angle: -45)

    NSColor(red: 0.25, green: 0.45, blue: 0.95, alpha: 0.4).setStroke()
    chipPath.lineWidth = max(1.0, size * 0.012)
    chipPath.stroke()

    // Draw pulsing pulse wave / telemetry line across the chip
    let wavePath = NSBezierPath()
    let midY = chipRect.midY
    let minX = chipRect.minX + chipRect.width * 0.12
    let maxX = chipRect.maxX - chipRect.width * 0.12
    let width = maxX - minX

    wavePath.move(to: NSPoint(x: minX, y: midY))
    wavePath.line(to: NSPoint(x: minX + width * 0.22, y: midY))
    wavePath.line(to: NSPoint(x: minX + width * 0.32, y: midY + chipRect.height * 0.26))
    wavePath.line(to: NSPoint(x: minX + width * 0.46, y: midY - chipRect.height * 0.30))
    wavePath.line(to: NSPoint(x: minX + width * 0.58, y: midY + chipRect.height * 0.38))
    wavePath.line(to: NSPoint(x: minX + width * 0.72, y: midY - chipRect.height * 0.15))
    wavePath.line(to: NSPoint(x: minX + width * 0.82, y: midY))
    wavePath.line(to: NSPoint(x: maxX, y: midY))

    // Glow under the wave
    if let ctx = context {
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: 0),
            blur: size * 0.04,
            color: NSColor(red: 0.18, green: 0.85, blue: 0.55, alpha: 0.85).cgColor
        )
        NSColor(red: 0.25, green: 0.90, blue: 0.60, alpha: 1.0).setStroke()
        wavePath.lineWidth = max(2.0, size * 0.035)
        wavePath.lineCapStyle = .round
        wavePath.lineJoinStyle = .round
        wavePath.stroke()
        ctx.restoreGState()
    }

    // Solid crisp wave stroke on top
    NSColor(red: 0.70, green: 1.0, blue: 0.80, alpha: 1.0).setStroke()
    wavePath.lineWidth = max(1.5, size * 0.02)
    wavePath.lineCapStyle = .round
    wavePath.stroke()

    // 4 CPU corner accent pins
    let pinLength = size * 0.04
    let pinColor = NSColor(red: 0.35, green: 0.60, blue: 1.0, alpha: 0.75)
    pinColor.setStroke()

    func drawPins(x: CGFloat, y1: CGFloat, y2: CGFloat) {
        let p = NSBezierPath()
        p.lineWidth = max(1.0, size * 0.01)
        p.move(to: NSPoint(x: x, y: y1))
        p.line(to: NSPoint(x: x, y: y1 + pinLength))
        p.move(to: NSPoint(x: x, y: y2))
        p.line(to: NSPoint(x: x, y: y2 - pinLength))
        p.stroke()
    }

    drawPins(x: chipRect.minX - size * 0.015, y1: chipRect.midY - size * 0.04, y2: chipRect.midY + size * 0.04)
    drawPins(x: chipRect.maxX + size * 0.015, y1: chipRect.midY - size * 0.04, y2: chipRect.midY + size * 0.04)

    context?.restoreGState()
    image.unlockFocus()
    return image
}

func savePNG(image: NSImage, path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        return
    }
    try? png.write(to: URL(fileURLWithPath: path))
}

let iconsetDir = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let sizes: [(String, CGFloat)] = [
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

for (filename, size) in sizes {
    let img = createIconImage(size: size)
    savePNG(image: img, path: "\(iconsetDir)/\(filename)")
}

print("Created all iconset files in \(iconsetDir)")
