import UIKit
import CoreML
import Accelerate
import simd

// MARK: - SHARP — 3D Gaussian View Synthesis
// SHARP (Sharp Monocular View Synthesis) is Apple's research model that generates
// 3D Gaussian splat representations from a single image.
// Official Core ML conversion is not yet published; this processor demonstrates
// the concept and provides a simulated rendering pipeline.
//
// Reference: https://github.com/apple/ml-sharp

struct SHARPFrame {
    let rendered: UIImage
    let cameraAngleH: Float   // degrees
    let cameraAngleV: Float
    let gaussianCount: Int
    let isSimulated: Bool
}

final class SHARPProcessor {

    // MARK: - State
    private var sourceImage: UIImage?
    private var gaussianField: [Gaussian3D] = []
    private(set) var isProcessed = false

    // MARK: - Gaussian primitive
    struct Gaussian3D {
        var position: SIMD3<Float>
        var color: SIMD4<Float>      // RGBA
        var scale: SIMD3<Float>
        var opacity: Float
    }

    // MARK: - Fit (simulated)
    /// In a real deployment: load the .pt → convert with coremltools → run MLModel
    func fit(image: UIImage) async {
        sourceImage = image
        gaussianField = await Task.detached(priority: .userInitiated) { [weak self] in
            self?.generateSimulatedGaussians(from: image) ?? []
        }.value
        isProcessed = true
    }

    // MARK: - Novel View Render
    func render(angleH: Float, angleV: Float) -> SHARPFrame? {
        guard let source = sourceImage, isProcessed else { return nil }
        let rendered = renderGaussians(gaussianField,
                                       angleH: angleH, angleV: angleV,
                                       sourceImage: source)
        return SHARPFrame(rendered: rendered,
                          cameraAngleH: angleH,
                          cameraAngleV: angleV,
                          gaussianCount: gaussianField.count,
                          isSimulated: true)
    }

    // MARK: - Simulated Gaussian generation
    private func generateSimulatedGaussians(from image: UIImage) -> [Gaussian3D] {
        guard let cgImage = image.cgImage else { return [] }
        let w = 64, h = 64
        guard let pixels = sampleImage(cgImage, width: w, height: h) else { return [] }

        var gaussians = [Gaussian3D]()
        gaussians.reserveCapacity(w * h)

        for y in 0..<h {
            for x in 0..<w {
                let idx = (y * w + x) * 4
                let r = Float(pixels[idx + 0]) / 255
                let g = Float(pixels[idx + 1]) / 255
                let b = Float(pixels[idx + 2]) / 255

                // Simulate depth from luminance (bright = near)
                let lum = 0.299 * r + 0.587 * g + 0.114 * b
                let depth = (1 - lum) * 2.0 - 1.0   // -1 (near) to 1 (far)

                let px = (Float(x) / Float(w) - 0.5) * 2
                let py = (Float(y) / Float(h) - 0.5) * 2

                let g3d = Gaussian3D(
                    position: SIMD3(px, -py, depth),
                    color: SIMD4(r, g, b, 1.0),
                    scale: SIMD3(0.04, 0.04, 0.04),
                    opacity: 0.6 + Float.random(in: 0...0.4)
                )
                gaussians.append(g3d)
            }
        }
        return gaussians
    }

    // MARK: - Simulated Gaussian splatting render
    private func renderGaussians(_ gaussians: [Gaussian3D],
                                 angleH: Float, angleV: Float,
                                 sourceImage: UIImage) -> UIImage {
        let size = CGSize(width: 512, height: 512)

        UIGraphicsBeginImageContextWithOptions(size, false, 1)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return sourceImage }

        // Draw source image as base layer with perspective-simulated shift
        let shiftX = CGFloat(angleH) / 45.0 * 40
        let shiftY = CGFloat(angleV) / 30.0 * 20
        sourceImage.draw(in: CGRect(x: -shiftX, y: -shiftY,
                                    width: size.width + abs(shiftX) * 2,
                                    height: size.height + abs(shiftY) * 2))

        // Overlay Gaussian splats for parallax depth effect
        let cosH = cos(angleH * .pi / 180)
        let sinH = sin(angleH * .pi / 180)

        for gaussian in gaussians.prefix(2000) {
            // Rotate position by camera angle
            let rx = gaussian.position.x * cosH - gaussian.position.z * sinH
            let rz = gaussian.position.x * sinH + gaussian.position.z * cosH

            // Project to 2D
            let fov: Float = 1.2
            let projX = rx / (rz + 3) * fov
            let projY = gaussian.position.y / (rz + 3) * fov

            let sx = CGFloat((projX + 1) * 0.5) * size.width
            let sy = CGFloat((projY + 1) * 0.5) * size.height

            let radius = CGFloat(gaussian.scale.x / (rz + 3) * fov) * size.width * 0.5
            let clampedRadius = max(0.5, min(radius, 8))

            let color = UIColor(
                red: CGFloat(gaussian.color.x),
                green: CGFloat(gaussian.color.y),
                blue: CGFloat(gaussian.color.z),
                alpha: CGFloat(gaussian.opacity) * 0.15
            )
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: sx - clampedRadius, y: sy - clampedRadius,
                                        width: clampedRadius * 2, height: clampedRadius * 2))
        }

        return UIGraphicsGetImageFromCurrentImageContext() ?? sourceImage
    }

    private func sampleImage(_ cgImage: CGImage, width: Int, height: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &pixels, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }
}
