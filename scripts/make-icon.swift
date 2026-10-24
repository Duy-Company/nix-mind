import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for (points, factor) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let pixels = points * factor
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels)/1024); transform.concat()
    let body = NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 208, yRadius: 208)
    NSGradient(starting: NSColor(srgbRed: 0.56, green: 0.45, blue: 0.93, alpha: 1), ending: NSColor(srgbRed: 0.34, green: 0.27, blue: 0.69, alpha: 1))!.draw(in: body, angle: -70)
    let positions = [NSPoint(x: 740, y: 735),NSPoint(x: 770, y: 512),NSPoint(x: 740, y: 289),NSPoint(x: 284, y: 735),NSPoint(x: 254, y: 512),NSPoint(x: 284, y: 289)]
    for end in positions {
        let path = NSBezierPath(); path.move(to: NSPoint(x: 512, y: 512))
        path.curve(to: end, controlPoint1: NSPoint(x: end.x, y: 512), controlPoint2: NSPoint(x: 512, y: end.y))
        NSColor.white.withAlphaComponent(0.6).setStroke(); path.lineWidth = 19; path.stroke()
        NSColor.white.withAlphaComponent(0.94).setFill(); NSBezierPath(roundedRect: NSRect(x: end.x-50,y:end.y-37,width:100,height:74), xRadius:22,yRadius:22).fill()
    }
    NSColor.white.setFill(); NSBezierPath(roundedRect: NSRect(x: 409,y:449,width:206,height:126), xRadius:35,yRadius:35).fill()
    NSGraphicsContext.restoreGraphicsState()
    let suffix = factor == 2 ? "@2x" : ""
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
}
