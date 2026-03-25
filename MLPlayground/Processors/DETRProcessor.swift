import CoreML
import Vision
import UIKit
import CoreImage
import SwiftUI

// MARK: - DETR ResNet-50 Semantic Segmentation

/// DETRResnet50SemanticSegmentationF16.mlpackage
/// Input:  (1, 3, 480, 480) image
/// Output: pixel_predictions — (480, 480) int32 class indices
final class DETRProcessor {

    // COCO + Things class labels (133 classes for panoptic)
    static let labels: [String] = {
        // First 80 are COCO object classes
        let obj = ["person","bicycle","car","motorcycle","airplane","bus","train","truck","boat",
                   "traffic light","fire hydrant","stop sign","parking meter","bench","bird","cat",
                   "dog","horse","sheep","cow","elephant","bear","zebra","giraffe","backpack",
                   "umbrella","handbag","tie","suitcase","frisbee","skis","snowboard","sports ball",
                   "kite","baseball bat","baseball glove","skateboard","surfboard","tennis racket",
                   "bottle","wine glass","cup","fork","knife","spoon","bowl","banana","apple",
                   "sandwich","orange","broccoli","carrot","hot dog","pizza","donut","cake","chair",
                   "couch","potted plant","bed","dining table","toilet","tv","laptop","mouse",
                   "remote","keyboard","cell phone","microwave","oven","toaster","sink",
                   "refrigerator","book","clock","vase","scissors","teddy bear","hair drier",
                   "toothbrush"]
        // Stuff classes (53)
        let stuff = ["banner","blanket","bridge","cardboard","counter","curtain","door-stuff",
                     "floor-wood","flower","fruit","gravel","house","light","mirror-stuff",
                     "net","pillow","platform","playingfield","railroad","river","road","roof",
                     "sand","sea","shelf","snow","stairs","tent","towel","wall-brick",
                     "wall-stone","wall-tile","wall-wood","water-other","window-blind",
                     "window-other","tree-merged","fence-merged","ceiling-merged","sky-other-merged",
                     "cabinet-merged","table-merged","floor-other-merged","pavement-merged",
                     "mountain-merged","grass-merged","dirt-merged","paper-merged",
                     "food-other-merged","building-other-merged","rock-merged",
                     "wall-other-merged","rug-merged"]
        return obj + stuff
    }()

    private var model: MLModel?
    private let modelManager = MLModelManager.shared

    func loadIfNeeded() async {
        guard model == nil else { return }
        await modelManager.prepare(.detr)
        model = modelManager.loadedModels[.detr]
    }

    func segment(pixelBuffer: CVPixelBuffer) async -> SegmentationResult? {
        guard let cgInput = pixelBuffer.toCGImage(),
              let resized = cgInput.toPixelBuffer(width: 480, height: 480) else { return nil }

        guard let model = model else {
            return mockResult(width: 480, height: 480)
        }

        do {
            let input = try MLDictionaryFeatureProvider(dictionary: [
                "image": MLFeatureValue(pixelBuffer: resized)
            ])
            let output = try await model.prediction(from: input)

            // pixel_predictions: (480, 480) multi-array of Int32
            if let multiArray = output.featureValue(for: "pixel_predictions")?.multiArrayValue {
                return buildResult(from: multiArray, width: 480, height: 480)
            }
        } catch {}

        return mockResult(width: 480, height: 480)
    }

    private func buildResult(from array: MLMultiArray, width: Int, height: Int) -> SegmentationResult {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var classSet = Set<Int>()

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                let classIdx = array[idx].intValue
                classSet.insert(classIdx)
                let color = segmentationPalette[classIdx % segmentationPalette.count]
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                color.getRed(&r, green: &g, blue: &b, alpha: &a)
                pixels[idx * 4 + 0] = UInt8(r * 255)
                pixels[idx * 4 + 1] = UInt8(g * 255)
                pixels[idx * 4 + 2] = UInt8(b * 255)
                pixels[idx * 4 + 3] = 200
            }
        }

        let mask = pixelsToImage(pixels: pixels, width: width, height: height)
        let labels = classSet.compactMap { idx -> (String, Color)? in
            guard idx < Self.labels.count else { return nil }
            return (Self.labels[idx], Color(segmentationPalette[idx % segmentationPalette.count]))
        }
        let classColors = Dictionary(labels.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })

        return SegmentationResult(mask: mask!, classColors: classColors,
                                  classLabels: labels.map(\.0))
    }

    private func mockResult(width: Int, height: Int) -> SegmentationResult {
        // Generate a colorful mock segmentation
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                let zone = (x / (width / 4)) + (y / (height / 4)) * 4
                let color = segmentationPalette[zone % segmentationPalette.count]
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
                color.getRed(&r, green: &g, blue: &b, alpha: nil)
                pixels[idx * 4 + 0] = UInt8(r * 255)
                pixels[idx * 4 + 1] = UInt8(g * 255)
                pixels[idx * 4 + 2] = UInt8(b * 255)
                pixels[idx * 4 + 3] = 180
            }
        }
        let mask = pixelsToImage(pixels: pixels, width: width, height: height)!
        return SegmentationResult(
            mask: mask,
            classColors: ["person": .red, "background": .blue, "sky": .cyan],
            classLabels: ["person", "background", "sky"]
        )
    }

    private func pixelsToImage(pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        var mutablePixels = pixels
        guard let provider = CGDataProvider(data: NSData(bytes: &mutablePixels,
                                                         length: mutablePixels.count)) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}
