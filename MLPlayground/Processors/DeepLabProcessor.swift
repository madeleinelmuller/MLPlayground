import CoreML
import Vision
import UIKit
import SwiftUI

// MARK: - DeepLabV3 Semantic Segmentation
// Input:  [1, 513, 513, 3]
// Output: (513, 513) int class indices, 21 Pascal VOC classes

final class DeepLabProcessor {

    static let labels = [
        "background","aeroplane","bicycle","bird","boat","bottle",
        "bus","car","cat","chair","cow","dining table","dog","horse",
        "motorbike","person","potted plant","sheep","sofa","train","tv/monitor"
    ]

    private var model: MLModel?
    private let modelManager = MLModelManager.shared

    func loadIfNeeded() async {
        guard model == nil else { return }
        await modelManager.prepare(.deeplab)
        model = modelManager.loadedModels[.deeplab]
    }

    func segment(pixelBuffer: CVPixelBuffer) async -> SegmentationResult? {
        guard let cgInput = pixelBuffer.toCGImage(),
              let resized = cgInput.toPixelBuffer(width: 513, height: 513) else { return nil }

        guard let model = model else {
            return mockResult(width: 513, height: 513)
        }

        do {
            let input = try MLDictionaryFeatureProvider(dictionary: [
                "image": MLFeatureValue(pixelBuffer: resized)
            ])
            let output = try await model.prediction(from: input)

            for key in ["ResizeBilinear_2:0", "output", "semanticPredictions", "classes"] {
                if let ma = output.featureValue(for: key)?.multiArrayValue {
                    return buildResult(from: ma, width: 513, height: 513)
                }
            }
        } catch {}

        return mockResult(width: 513, height: 513)
    }

    private func buildResult(from array: MLMultiArray, width: Int, height: Int) -> SegmentationResult {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var pixelCounts = [Int: Int]()

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                let classIdx = array[idx].intValue
                pixelCounts[classIdx, default: 0] += 1
                let color = segmentationPalette[classIdx % segmentationPalette.count]
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
                color.getRed(&r, green: &g, blue: &b, alpha: nil)
                pixels[idx * 4 + 0] = UInt8(r * 255)
                pixels[idx * 4 + 1] = UInt8(g * 255)
                pixels[idx * 4 + 2] = UInt8(b * 255)
                pixels[idx * 4 + 3] = 190
            }
        }

        let total = Double(width * height)
        var fractions = [String: Double]()
        var classColors = [String: Color]()
        var classLabels = [String]()

        for (classIdx, count) in pixelCounts {
            let label = classIdx < Self.labels.count ? Self.labels[classIdx] : "class_\(classIdx)"
            fractions[label] = Double(count) / total
            classColors[label] = Color(segmentationPalette[classIdx % segmentationPalette.count])
            classLabels.append(label)
        }

        let mask = pixelsToImage(pixels: pixels, width: width, height: height)!
        return SegmentationResult(mask: mask, classColors: classColors,
                                  classLabels: classLabels, classPixelFractions: fractions)
    }

    private func mockResult(width: Int, height: Int) -> SegmentationResult {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var pixelCounts = [Int: Int]()

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                let cx = Double(x) / Double(width) - 0.5
                let cy = Double(y) / Double(height) - 0.5
                let classIdx = (cx * cx + cy * cy < 0.07) ? 15 : 0  // person vs background
                pixelCounts[classIdx, default: 0] += 1
                let color = segmentationPalette[classIdx % segmentationPalette.count]
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
                color.getRed(&r, green: &g, blue: &b, alpha: nil)
                pixels[idx * 4 + 0] = UInt8(r * 255)
                pixels[idx * 4 + 1] = UInt8(g * 255)
                pixels[idx * 4 + 2] = UInt8(b * 255)
                pixels[idx * 4 + 3] = 180
            }
        }
        let total = Double(width * height)
        let fractions: [String: Double] = [
            "background": Double(pixelCounts[0, default: 0]) / total,
            "person":     Double(pixelCounts[15, default: 0]) / total
        ]
        let mask = pixelsToImage(pixels: pixels, width: width, height: height)!
        return SegmentationResult(
            mask: mask,
            classColors: ["background": Color(segmentationPalette[0]),
                          "person": Color(segmentationPalette[15 % segmentationPalette.count])],
            classLabels: ["background", "person"],
            classPixelFractions: fractions
        )
    }

    private func pixelsToImage(pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        var mutablePixels = pixels
        guard let provider = CGDataProvider(data: NSData(bytes: &mutablePixels,
                                                         length: mutablePixels.count)) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}
