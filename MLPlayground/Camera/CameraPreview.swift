import SwiftUI
import AVFoundation

// MARK: - Live Camera Preview

struct CameraPreview: UIViewRepresentable {
    let cameraManager: CameraManager

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = cameraManager.makePreviewLayer().session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Frozen Frame View (shows last captured CGImage)

struct FrozenFrameView: View {
    let image: CGImage?

    var body: some View {
        if let image {
            Image(decorative: image, scale: 1, orientation: .up)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle()
                .fill(.black)
                .overlay {
                    ProgressView()
                        .tint(.white)
                }
        }
    }
}
