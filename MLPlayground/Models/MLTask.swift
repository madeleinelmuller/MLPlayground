import SwiftUI
import CoreML

// MARK: - ML Task Definitions

enum MLTask: String, CaseIterable, Identifiable {
    case sharp        = "SHARP"
    case detr         = "DETR"
    case deeplab      = "DeepLabV3"
    case yolo         = "YOLOv3"
    case depth        = "DepthAnythingV2"
    case fastvit      = "FastViT"
    case spatialLM    = "SpatialLM"

    var id: String { rawValue }

    // MARK: Display

    var title: String {
        switch self {
        case .sharp:     return "SHARP"
        case .detr:      return "DETR"
        case .deeplab:   return "DeepLabV3"
        case .yolo:      return "YOLOv3"
        case .depth:     return "Depth Anything V2"
        case .fastvit:   return "FastViT"
        case .spatialLM: return "SpatialLM"
        }
    }

    var subtitle: String {
        switch self {
        case .sharp:     return "3D View Synthesis"
        case .detr:      return "Semantic Segmentation"
        case .deeplab:   return "Scene Segmentation"
        case .yolo:      return "Object Detection"
        case .depth:     return "Depth Estimation"
        case .fastvit:   return "Image Classification"
        case .spatialLM: return "Spatial Scene Understanding"
        }
    }

    var description: String {
        switch self {
        case .sharp:
            return "Generate novel 3D views from a single photo using Gaussian splat representations."
        case .detr:
            return "Detect and segment every object class using a transformer encoder-decoder architecture."
        case .deeplab:
            return "Pixel-perfect semantic segmentation with atrous convolutions and ASPP pooling."
        case .yolo:
            return "Real-time multi-object detection across 80 COCO classes at 30+ FPS."
        case .depth:
            return "Estimate per-pixel depth from any single image — no stereo or LiDAR required."
        case .fastvit:
            return "Classify the scene using a fast hybrid vision transformer via structural reparameterization."
        case .spatialLM:
            return "Understand 3D spatial relationships, oriented object bounding boxes and room structure."
        }
    }

    var systemIcon: String {
        switch self {
        case .sharp:     return "cube.transparent.fill"
        case .detr:      return "circle.hexagonpath.fill"
        case .deeplab:   return "paintpalette.fill"
        case .yolo:      return "viewfinder.circle.fill"
        case .depth:     return "water.waves"
        case .fastvit:   return "brain.fill"
        case .spatialLM: return "map.fill"
        }
    }

    // MARK: Colours (per-task identity)

    var primaryColor: Color {
        switch self {
        case .sharp:     return Color(hue: 0.72, saturation: 0.80, brightness: 0.95)
        case .detr:      return Color(hue: 0.06, saturation: 0.90, brightness: 0.95)
        case .deeplab:   return Color(hue: 0.42, saturation: 0.80, brightness: 0.80)
        case .yolo:      return Color(hue: 0.08, saturation: 1.00, brightness: 1.00)
        case .depth:     return Color(hue: 0.57, saturation: 0.90, brightness: 1.00)
        case .fastvit:   return Color(hue: 0.14, saturation: 0.95, brightness: 1.00)
        case .spatialLM: return Color(hue: 0.75, saturation: 0.85, brightness: 0.90)
        }
    }

    var secondaryColor: Color {
        switch self {
        case .sharp:     return Color(hue: 0.85, saturation: 0.70, brightness: 0.85)
        case .detr:      return Color(hue: 0.80, saturation: 0.60, brightness: 0.90)
        case .deeplab:   return Color(hue: 0.55, saturation: 0.75, brightness: 0.85)
        case .yolo:      return Color(hue: 0.00, saturation: 0.90, brightness: 0.90)
        case .depth:     return Color(hue: 0.50, saturation: 0.80, brightness: 0.90)
        case .fastvit:   return Color(hue: 0.05, saturation: 0.90, brightness: 1.00)
        case .spatialLM: return Color(hue: 0.67, saturation: 0.70, brightness: 0.80)
        }
    }

    var tertiaryColor: Color {
        switch self {
        case .sharp:     return Color(hue: 0.60, saturation: 0.50, brightness: 0.70)
        case .detr:      return Color(hue: 0.10, saturation: 0.50, brightness: 0.60)
        case .deeplab:   return Color(hue: 0.35, saturation: 0.60, brightness: 0.60)
        case .yolo:      return Color(hue: 0.12, saturation: 0.70, brightness: 0.70)
        case .depth:     return Color(hue: 0.62, saturation: 0.60, brightness: 0.70)
        case .fastvit:   return Color(hue: 0.20, saturation: 0.70, brightness: 0.80)
        case .spatialLM: return Color(hue: 0.80, saturation: 0.50, brightness: 0.60)
        }
    }

    // MARK: Model Download

    var modelDownloadURL: URL? {
        switch self {
        case .detr:
            return URL(string: "https://ml-assets.apple.com/coreml/models/Image/Segmentation/DETR/DETRResnet50SemanticSegmentationF16.mlpackage.zip")
        case .deeplab:
            return URL(string: "https://ml-assets.apple.com/coreml/models/Image/ImageSegmentation/DeepLabV3/DeepLabV3Int8LUT.mlmodel")
        case .yolo:
            return URL(string: "https://ml-assets.apple.com/coreml/models/Image/ObjectDetection/YOLOv3/YOLOv3.mlmodel")
        case .depth:
            return URL(string: "https://ml-assets.apple.com/coreml/models/Image/DepthEstimation/DepthAnything/DepthAnythingV2SmallF16.mlpackage.zip")
        case .fastvit:
            return URL(string: "https://ml-assets.apple.com/coreml/models/Image/ImageClassification/FastViT/FastViTT8F16.mlpackage.zip")
        case .sharp, .spatialLM:
            return nil   // No official Core ML package yet; demos use ARKit / custom pipelines
        }
    }

    var modelFilename: String {
        switch self {
        case .sharp:     return "SHARP"
        case .detr:      return "DETRResnet50SemanticSegmentationF16"
        case .deeplab:   return "DeepLabV3"
        case .yolo:      return "YOLOv3"
        case .depth:     return "DepthAnythingV2SmallF16"
        case .fastvit:   return "FastViTT8F16"
        case .spatialLM: return "SpatialLM"
        }
    }

    var requiresCamera: Bool { true }

    var requiresLiDAR: Bool {
        self == .spatialLM
    }

    var inputSize: CGSize {
        switch self {
        case .sharp:     return CGSize(width: 512, height: 512)
        case .detr:      return CGSize(width: 480, height: 480)
        case .deeplab:   return CGSize(width: 513, height: 513)
        case .yolo:      return CGSize(width: 416, height: 416)
        case .depth:     return CGSize(width: 518, height: 518)
        case .fastvit:   return CGSize(width: 256, height: 256)
        case .spatialLM: return CGSize(width: 640, height: 480)
        }
    }
}

// MARK: - Detection Results

struct DetectedObject: Identifiable {
    let id = UUID()
    let label: String
    let confidence: Float
    let boundingBox: CGRect
    let color: Color
}

struct SegmentationResult {
    let mask: CGImage
    let classColors: [String: Color]
    let classLabels: [String]
}

struct DepthResult {
    let depthMap: CGImage
    let minDepth: Float
    let maxDepth: Float
}

struct ClassificationResult {
    let topK: [(label: String, confidence: Float)]
}

struct SpatialResult {
    struct BoundingBox3D: Identifiable {
        let id = UUID()
        let label: String
        let center: SIMD3<Float>
        let extent: SIMD3<Float>
        let yaw: Float
        let color: Color
    }
    let objects: [BoundingBox3D]
    let roomDescription: String
}
