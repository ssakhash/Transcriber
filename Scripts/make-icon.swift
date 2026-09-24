import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let box = NSBezierPath(roundedRect: NSRect(x: 62, y: 62, width: 900, height: 900), xRadius: 202, yRadius: 202)
        NSGradient(starting: NSColor(red: 0.13, green: 0.19, blue: 0.2, alpha: 1),
                   ending: NSColor(red: 0.035, green: 0.055, blue: 0.067, alpha: 1))!.draw(in: box, angle: -90)
        NSColor(white: 1, alpha: 0.12).setStroke(); box.lineWidth = 4; box.stroke()
        let mint = NSColor(red: 0.49, green: 0.94, blue: 0.79, alpha: 1)
        mint.setStroke()
        let bubble = NSBezierPath(roundedRect: NSRect(x: 220, y: 290, width: 585, height: 445), xRadius: 75, yRadius: 75)
        bubble.lineWidth = 30; bubble.stroke()
        let tail = NSBezierPath(); tail.move(to: NSPoint(x: 325, y: 295)); tail.line(to: NSPoint(x: 325, y: 205)); tail.line(to: NSPoint(x: 440, y: 295))
        tail.lineWidth = 30; tail.lineJoinStyle = .round; tail.lineCapStyle = .round; tail.stroke()
        for (x, height) in [(315.0, 95.0), (405.0, 180.0), (495.0, 265.0), (585.0, 150.0), (675.0, 80.0)] {
            mint.withAlphaComponent(x == 495 ? 1 : 0.65).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 510 - height / 2, width: 35, height: height), xRadius: 17, yRadius: 17).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
