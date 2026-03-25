import CoreML
import Vision
import UIKit
import SwiftUI

// MARK: - YOLO v3 Object Detector

/// Wraps Apple's YOLOv3.mlmodel (416×416 input, 80 COCO classes).
/// Uses Vision's VNCoreMLRequest which handles resizing and NMS internally.
final class YOLOProcessor {

    private var visionModel: VNCoreMLModel?
    private let modelManager = MLModelManager.shared

    // MARK: - Load

    func loadIfNeeded() async {
        guard visionModel == nil else { return }
        await modelManager.prepare(.yolo)
        guard let model = modelManager.loadedModels[.yolo] else { return }
        visionModel = try? VNCoreMLModel(for: model)
    }

    // MARK: - Process

    func detect(in pixelBuffer: CVPixelBuffer) async -> [DetectedObject] {
        guard let visionModel = visionModel else { return mockDetections() }
        return await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: visionModel) { req, _ in
                let observations = req.results as? [VNRecognizedObjectObservation] ?? []
                let objects = observations.prefix(15).map { obs -> DetectedObject in
                    let label = obs.labels.first?.identifier ?? "unknown"
                    let confidence = obs.labels.first?.confidence ?? 0
                    let box = obs.boundingBox
                    // Vision uses bottom-left origin; flip Y for UIKit
                    let rect = CGRect(
                        x: box.minX,
                        y: 1 - box.maxY,
                        width: box.width,
                        height: box.height
                    )
                    let colorIdx = abs(label.hashValue) % segmentationPalette.count
                    return DetectedObject(
                        label: label,
                        confidence: confidence,
                        boundingBox: rect,
                        color: Color(segmentationPalette[colorIdx])
                    )
                }
                continuation.resume(returning: Array(objects))
            }
            request.imageCropAndScaleOption = .scaleFit
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            try? handler.perform([request])
        }
    }

    // MARK: - Mock (when model not loaded)

    private func mockDetections() -> [DetectedObject] {
        let items: [(String, CGRect)] = [
            ("person",    CGRect(x: 0.10, y: 0.10, width: 0.35, height: 0.65)),
            ("laptop",    CGRect(x: 0.55, y: 0.45, width: 0.30, height: 0.25)),
            ("cup",       CGRect(x: 0.70, y: 0.70, width: 0.12, height: 0.18)),
        ]
        return items.map { label, box in
            let colorIdx = abs(label.hashValue) % segmentationPalette.count
            return DetectedObject(label: label, confidence: Float.random(in: 0.75...0.99),
                                  boundingBox: box, color: Color(segmentationPalette[colorIdx]))
        }
    }
}
