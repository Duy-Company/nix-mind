import AppKit
import Foundation

/// Offscreen rendering benchmark. Does not open or modify the source document.
@main struct CanvasPerformanceTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
        let book = try MapFormats.decodeBook(Data(contentsOf: fixture), type: MapFormats.nativeType)
        let store = MapStore(); store.load(book)
        let canvas = MindMapCanvas(store: store)
        canvas.frame = CGRect(x: 0, y: 0, width: 1100, height: 740); canvas.layout(); canvas.fit()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1100, pixelsHigh: 740, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        context.cgContext.translateBy(x: 0, y: 740); context.cgContext.scaleBy(x: 1, y: -1)
        let flipped = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        func draw() {
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = flipped
            context.cgContext.saveGState(); context.cgContext.clip(to: canvas.bounds)
            canvas.draw(canvas.bounds)
            context.cgContext.restoreGState(); NSGraphicsContext.restoreGraphicsState()
        }
        func elapsed(_ body: () -> Void) -> Double {
            let start = DispatchTime.now().uptimeNanoseconds; body()
            return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        }
        func measure(_ body: () -> Void) -> [String: Double] {
            var samples: [Double] = []
            for _ in 0..<12 { samples.append(elapsed(body)) }
            samples.sort()
            return ["median_ms": samples[samples.count / 2], "p95_ms": samples.last!, "mean_ms": samples.reduce(0,+) / Double(samples.count)]
        }
        let fitZoom = canvas.scale
        draw() // Warm up fonts and the render cache.
        let overview = measure { canvas.pan.x += 13; canvas.pan.y += 5; draw() }
        canvas.setZoom(0.7); canvas.center(on: store.map.root.id); draw()
        let detail = measure { canvas.pan.x += 17; canvas.pan.y += 7; draw() }
        let accessibility = measure { _ = canvas.accessibilityChildren() }
        let zoom = measure { canvas.setZoom(canvas.scale == 0.7 ? 0.8 : 0.7); draw() }
        let result: [String: Any] = ["fixture": fixture.lastPathComponent, "topic_count": store.map.topics.count, "fit_zoom": fitZoom, "overview_pan": overview, "detail_pan": detail, "zoom": zoom, "accessibility": accessibility]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data); print("")
    }
}
