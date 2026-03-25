import AVFoundation
import UIKit
import CoreImage

// MARK: - Camera Manager

@Observable
final class CameraManager: NSObject {

    enum Status {
        case unconfigured, configured, running, stopped, failed(Error)
    }

    var status: Status = .unconfigured
    var currentFrame: CGImage?
    var currentPixelBuffer: CVPixelBuffer?

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.mlplayground.camera", qos: .userInteractive)
    private var frameCallback: ((CVPixelBuffer) -> Void)?

    // MARK: - Setup

    func start(position: AVCaptureDevice.Position = .back) async {
        guard await requestAccess() else {
            status = .failed(NSError(domain: "Camera", code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: "Camera access denied"]))
            return
        }
        configure(position: position)
        session.startRunning()
        status = .running
    }

    func stop() {
        session.stopRunning()
        status = .stopped
    }

    func setFrameCallback(_ callback: @escaping (CVPixelBuffer) -> Void) {
        frameCallback = callback
    }

    // MARK: - Private

    private func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    private func configure(position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        // Device
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        // Output
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        // Orientation
        if let connection = videoOutput.connection(with: .video) {
            connection.videoRotationAngle = 90
            connection.isVideoMirrored = (position == .front)
        }

        session.commitConfiguration()
        status = .configured
    }

    // MARK: - Layer

    func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }
}

// MARK: - Sample Buffer Delegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            DispatchQueue.main.async { [weak self] in
                self?.currentFrame = cgImage
                self?.currentPixelBuffer = pixelBuffer
            }
        }

        frameCallback?(pixelBuffer)
    }
}
