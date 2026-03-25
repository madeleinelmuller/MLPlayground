import SwiftUI
import UIKit

// MARK: - Live Background State
// An @Observable class that each demo view feeds with its current ML results.
// AnimatedBackground reads the blobs and renders them as positional coloured splats,
// creating a background that visually mirrors what the model is "seeing".

@Observable
final class LiveBackgroundState {

    struct Blob: Equatable {
        var color: Color = .clear
        var weight: Double = 0      // 0 = invisible, 1 = full size/opacity
        var x: Double = 0.5         // normalized 0–1 (left→right)
        var y: Double = 0.5         // normalized 0–1 (top→bottom)

        static let empty = Blob()
    }

    // Fixed 8 slots so SwiftUI can animate property changes per-slot rather than
    // diffing a fully-replaced array every frame.
    var blobs: [Blob] = Array(repeating: .empty, count: 8)
    var isActive: Bool = false

    private var lastUpdate: Date = .distantPast
    private let throttle: TimeInterval = 0.12  // ≤8 updates / sec

    // MARK: - YOLO Object Detection
    // One blob per detection, positioned at the bbox centre, sized by area.
    func update(detections: [DetectedObject]) {
        guard throttleCheck() else { return }

        var next = Array(repeating: Blob.empty, count: 8)
        let sorted = detections.sorted {
            $0.boundingBox.width * $0.boundingBox.height >
            $1.boundingBox.width * $1.boundingBox.height
        }
        for (i, det) in sorted.prefix(8).enumerated() {
            let area = Double(det.boundingBox.width * det.boundingBox.height)
            next[i] = Blob(
                color: det.color,
                weight: (area * 3.5 + 0.25).clamped(0.2...1.0),
                x: Double(det.boundingBox.midX),
                y: Double(det.boundingBox.midY)
            )
        }
        commit(next, active: !detections.isEmpty)
    }

    // MARK: - Segmentation (DETR / DeepLabV3)
    // Blobs sized by class pixel fraction; arranged in a ring so dominant
    // classes sit closer to the centre (= larger blur = more background influence).
    func update(segResult: SegmentationResult) {
        guard throttleCheck() else { return }

        var next = Array(repeating: Blob.empty, count: 8)
        let sorted = segResult.classPixelFractions
            .sorted { $0.value > $1.value }
        let count = max(1, sorted.count)

        for (i, (label, fraction)) in sorted.prefix(8).enumerated() {
            let color = segResult.classColors[label] ?? .gray
            let angle = (Double(i) / Double(count)) * 2 * .pi
            // Dominant class (i=0) stays near centre; minor classes orbit further out
            let r = 0.15 + Double(i) / Double(count) * 0.35
            next[i] = Blob(
                color: color,
                weight: (fraction * 2.8).clamped(0.15...1.0),
                x: (0.5 + cos(angle) * r).clamped(0.05...0.95),
                y: (0.5 + sin(angle) * r * 0.75).clamped(0.05...0.95)
            )
        }
        commit(next, active: true)
    }

    // MARK: - Depth Estimation
    // Sample the rendered false-colour depth image on a 3×3 grid → 9 blobs
    // at matching screen positions.  The turbo colourmap already encodes
    // near=red/orange and far=blue/purple, so the background picks those up.
    func update(depthResult: DepthResult) {
        guard throttleCheck() else { return }

        let samples = sampleGrid(cgImage: depthResult.depthMap, cols: 3, rows: 3)
        var next = Array(repeating: Blob.empty, count: 8)
        for (i, s) in samples.prefix(8).enumerated() {
            next[i] = Blob(color: s.color, weight: 0.60, x: s.x, y: s.y)
        }
        commit(next, active: true)
    }

    // MARK: - Classification (FastViT)
    // Top-k classes each get a blob; weight = confidence; hue mapped from
    // the label's semantic category so "cat" ≠ "car" ≠ "sky".
    func update(classResult: ClassificationResult) {
        guard throttleCheck() else { return }

        var next = Array(repeating: Blob.empty, count: 8)
        let topK = classResult.topK.prefix(8)
        let n = max(1, topK.count)

        for (i, pred) in topK.enumerated() {
            let hue = semanticHue(for: pred.label)
            let conf = Double(pred.confidence)
            let angle = (Double(i) / Double(n)) * 2 * .pi - (.pi / 2)
            let r = 0.28 + conf * 0.18
            next[i] = Blob(
                color: Color(hue: hue, saturation: 0.80, brightness: 0.95),
                weight: conf.clamped(0.05...1.0),
                x: (0.5 + cos(angle) * r).clamped(0.05...0.95),
                y: (0.5 + sin(angle) * r * 0.8).clamped(0.05...0.95)
            )
        }
        commit(next, active: true)
    }

    // MARK: - SHARP rendered frame
    // 3×3 colour samples from the synthesised view → the background mirrors
    // the photo's palette and shifts as the camera angle changes.
    func update(frame: UIImage) {
        guard throttleCheck() else { return }
        guard let cg = frame.cgImage else { return }

        let samples = sampleGrid(cgImage: cg, cols: 3, rows: 3)
        var next = Array(repeating: Blob.empty, count: 8)
        for (i, s) in samples.prefix(8).enumerated() {
            next[i] = Blob(color: s.color, weight: 0.55, x: s.x, y: s.y)
        }
        commit(next, active: true)
    }

    // MARK: - SpatialLM 3D scene
    // Objects projected from 3D world space onto a normalised top-down view.
    // Volume drives the blob weight; colour matches the object swatch.
    func update(spatial: SpatialResult) {
        guard throttleCheck() else { return }

        var next = Array(repeating: Blob.empty, count: 8)
        let sorted = spatial.objects.sorted {
            ($0.extent.x * $0.extent.y * $0.extent.z) >
            ($1.extent.x * $1.extent.y * $1.extent.z)
        }
        for (i, obj) in sorted.prefix(8).enumerated() {
            let vol = Double(obj.extent.x * obj.extent.y * obj.extent.z)
            let nx = Double((obj.center.x + 3.0) / 6.0).clamped(0.05...0.95)
            let nz = Double((obj.center.z + 3.0) / 6.0).clamped(0.05...0.95)
            next[i] = Blob(
                color: obj.color,
                weight: (sqrt(vol) * 0.55 + 0.15).clamped(0.15...1.0),
                x: nx,
                y: nz
            )
        }
        commit(next, active: !spatial.objects.isEmpty)
    }

    // MARK: - Internals

    private func throttleCheck() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastUpdate) >= throttle else { return false }
        lastUpdate = now
        return true
    }

    private func commit(_ next: [Blob], active: Bool) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
            blobs = next
            isActive = active
        }
    }

    // MARK: - Grid sampler

    private struct GridSample { var color: Color; var x, y: Double }

    private func sampleGrid(cgImage: CGImage, cols: Int, rows: Int) -> [GridSample] {
        let w = cgImage.width, h = cgImage.height
        guard w > 0, h > 0,
              let dataRef = cgImage.dataProvider?.data else { return [] }

        let raw = CFDataGetBytePtr(dataRef)!
        let bpr = cgImage.bytesPerRow
        let bpp = cgImage.bitsPerPixel / 8   // bytes per pixel

        var results = [GridSample]()
        for row in 0..<rows {
            for col in 0..<cols {
                let px = min(w - 1, col * w / cols + w / cols / 2)
                let py = min(h - 1, row * h / rows + h / rows / 2)
                let off = py * bpr + px * bpp

                let r = Double(raw[off    ]) / 255.0
                let g = Double(raw[off + 1]) / 255.0
                let b = Double(raw[off + 2]) / 255.0

                let nx = (Double(col) + 0.5) / Double(cols)
                let ny = (Double(row) + 0.5) / Double(rows)
                results.append(GridSample(color: Color(red: r, green: g, blue: b), x: nx, y: ny))
            }
        }
        return results
    }

    // MARK: - Semantic hue mapping (for classification)

    private func semanticHue(for label: String) -> Double {
        let l = label.lowercased()
        if l.contains("cat") || l.contains("dog") || l.contains("animal")     { return 0.08 }
        if l.contains("car") || l.contains("truck") || l.contains("bus")      { return 0.60 }
        if l.contains("person") || l.contains("human") || l.contains("face")  { return 0.97 }
        if l.contains("plant") || l.contains("tree") || l.contains("grass")   { return 0.35 }
        if l.contains("food") || l.contains("fruit") || l.contains("pizza")   { return 0.07 }
        if l.contains("water") || l.contains("ocean") || l.contains("sea")    { return 0.57 }
        if l.contains("sky") || l.contains("cloud")                           { return 0.62 }
        if l.contains("building") || l.contains("house") || l.contains("wall"){ return 0.10 }
        if l.contains("bird") || l.contains("fly") || l.contains("plane")     { return 0.52 }
        if l.contains("sports") || l.contains("ball") || l.contains("game")   { return 0.13 }
        return Double(abs(l.hashValue % 100)) / 100.0
    }
}

// MARK: - Double helper

private extension Double {
    func clamped(_ range: ClosedRange<Double>) -> Double {
        Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}
