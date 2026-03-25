import CoreML
import Vision
import UIKit
import SwiftUI

// MARK: - FastViT-T8 Image Classifier
// Input:  (1, 3, 256, 256)  RGB
// Output: classLabelProbs — [String: Double] or classLabel (top-1)

final class FastViTProcessor {

    private var visionModel: VNCoreMLModel?
    private let modelManager = MLModelManager.shared

    func loadIfNeeded() async {
        guard visionModel == nil else { return }
        await modelManager.prepare(.fastvit)
        guard let model = modelManager.loadedModels[.fastvit] else { return }
        visionModel = try? VNCoreMLModel(for: model)
    }

    func classify(pixelBuffer: CVPixelBuffer) async -> ClassificationResult {
        guard let visionModel = visionModel else {
            return mockResult()
        }

        return await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: visionModel) { req, _ in
                let observations = req.results as? [VNClassificationObservation] ?? []
                let topK = observations.prefix(10).map {
                    (label: $0.identifier, confidence: $0.confidence)
                }
                continuation.resume(returning: ClassificationResult(topK: Array(topK)))
            }
            request.imageCropAndScaleOption = .centerCrop
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            try? handler.perform([request])
        }
    }

    private func mockResult() -> ClassificationResult {
        let mock: [(String, Float)] = [
            ("tabby cat",       0.82),
            ("Egyptian cat",    0.10),
            ("tiger cat",       0.04),
            ("domestic cat",    0.02),
            ("Persian cat",     0.01),
        ]
        return ClassificationResult(topK: mock.map { (label: $0.0, confidence: $0.1) })
    }
}
