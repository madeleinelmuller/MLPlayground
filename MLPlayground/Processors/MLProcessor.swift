import CoreML
import Vision
import UIKit
import CoreImage

// MARK: - Base Processor Protocol

protocol MLProcessor {
    associatedtype Output
    func process(pixelBuffer: CVPixelBuffer) async throws -> Output
}

// MARK: - Shared helpers

extension CGImage {
    /// Resize to target size, returning a new CVPixelBuffer
    func toPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         width, height,
                                         kCVPixelFormatType_32BGRA,
                                         attrs as CFDictionary,
                                         &buffer)
        guard status == kCVReturnSuccess, let pixelBuffer = buffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer),
                                width: width, height: height,
                                bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue |
                                            CGBitmapInfo.byteOrder32Little.rawValue)
        context?.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        return pixelBuffer
    }
}

extension CVPixelBuffer {
    func toCGImage() -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: self)
        return CIContext().createCGImage(ciImage, from: ciImage.extent)
    }

    func resized(to size: CGSize) -> CVPixelBuffer? {
        guard let cgImage = toCGImage() else { return nil }
        return cgImage.toPixelBuffer(width: Int(size.width), height: Int(size.height))
    }
}

// MARK: - Colour palette for segmentation classes

let segmentationPalette: [UIColor] = [
    UIColor(red: 0.902, green: 0.098, blue: 0.294, alpha: 1),
    UIColor(red: 0.235, green: 0.706, blue: 0.294, alpha: 1),
    UIColor(red: 1.000, green: 0.882, blue: 0.098, alpha: 1),
    UIColor(red: 0.000, green: 0.510, blue: 0.784, alpha: 1),
    UIColor(red: 0.961, green: 0.510, blue: 0.188, alpha: 1),
    UIColor(red: 0.569, green: 0.118, blue: 0.706, alpha: 1),
    UIColor(red: 0.275, green: 0.941, blue: 0.941, alpha: 1),
    UIColor(red: 0.941, green: 0.196, blue: 0.902, alpha: 1),
    UIColor(red: 0.824, green: 0.961, blue: 0.235, alpha: 1),
    UIColor(red: 0.980, green: 0.745, blue: 0.745, alpha: 1),
    UIColor(red: 0.000, green: 0.502, blue: 0.502, alpha: 1),
    UIColor(red: 0.902, green: 0.745, blue: 1.000, alpha: 1),
    UIColor(red: 0.667, green: 0.431, blue: 0.157, alpha: 1),
    UIColor(red: 1.000, green: 0.980, blue: 0.784, alpha: 1),
    UIColor(red: 0.502, green: 0.000, blue: 0.000, alpha: 1),
    UIColor(red: 0.667, green: 1.000, blue: 0.765, alpha: 1),
    UIColor(red: 0.502, green: 0.502, blue: 0.000, alpha: 1),
    UIColor(red: 1.000, green: 0.847, blue: 0.694, alpha: 1),
    UIColor(red: 0.000, green: 0.000, blue: 0.502, alpha: 1),
    UIColor(red: 0.502, green: 0.502, blue: 0.502, alpha: 1),
]
