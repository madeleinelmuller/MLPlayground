import Foundation
import CoreML

// MARK: - Model State

enum ModelState: Equatable {
    case idle
    case downloading(progress: Double)
    case loading
    case ready
    case failed(String)

    var isReady: Bool { self == .ready }
    var isBusy: Bool {
        switch self {
        case .downloading, .loading: return true
        default: return false
        }
    }
}

// MARK: - Model Manager

@Observable
final class MLModelManager {

    static let shared = MLModelManager()

    var states: [MLTask: ModelState] = {
        Dictionary(uniqueKeysWithValues: MLTask.allCases.map { ($0, .idle) })
    }()

    var loadedModels: [MLTask: MLModel] = [:]

    private let modelsDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("MLModels", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // Retain download tasks and their KVO observations for the lifetime of the download.
    private var downloadTasks: [MLTask: URLSessionDownloadTask] = [:]
    private var downloadObservations: [MLTask: NSKeyValueObservation] = [:]

    // MARK: - Public

    func prepare(_ task: MLTask) async {
        guard case .idle = states[task] else { return }

        // SHARP and SpatialLM use custom pipelines (ARKit / algorithmic); no Core ML file needed.
        if task == .sharp || task == .spatialLM {
            states[task] = .ready
            return
        }

        guard let downloadURL = task.modelDownloadURL else {
            states[task] = .ready
            return
        }

        if cachedModelURL(for: task, downloadURL: downloadURL) != nil {
            await load(task)
        } else {
            await download(task, from: downloadURL)
        }
    }

    func state(for task: MLTask) -> ModelState {
        states[task] ?? .idle
    }

    // MARK: - Download

    private func download(_ task: MLTask, from url: URL) async {
        await MainActor.run { states[task] = .downloading(progress: 0) }

        do {
            let localZipOrModel = try await downloadFile(task: task, from: url)

            let finalURL: URL
            if url.pathExtension == "zip" {
                finalURL = try ZIPExtractor.extractModel(from: localZipOrModel, into: modelsDirectory)
                try? FileManager.default.removeItem(at: localZipOrModel)
            } else {
                finalURL = localZipOrModel
            }

            await load(task, from: finalURL)
        } catch {
            await MainActor.run { states[task] = .failed(error.localizedDescription) }
        }
    }

    /// Downloads `url` to the models directory, reporting progress via `states[task]`.
    /// Uses `URLSessionDownloadTask` with a properly-retained KVO observation.
    private func downloadFile(task: MLTask, from url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let destURL = modelsDirectory.appendingPathComponent(url.lastPathComponent)

            let dlTask = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, _, error in
                // Clean up retained objects regardless of outcome
                self?.downloadTasks.removeValue(forKey: task)
                self?.downloadObservations.removeValue(forKey: task)

                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let tempURL else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                do {
                    try? FileManager.default.removeItem(at: destURL)
                    try FileManager.default.moveItem(at: tempURL, to: destURL)
                    continuation.resume(returning: destURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            // Retain the task so the download keeps running after the continuation suspends.
            downloadTasks[task] = dlTask

            // Retain the observation in the class so it lives for the whole download.
            downloadObservations[task] = dlTask.observe(\.countOfBytesReceived,
                                                         options: [.new]) { [weak self] dt, _ in
                let total = dt.countOfBytesExpectedToReceive
                let progress = total > 0 ? Double(dt.countOfBytesReceived) / Double(total) : 0
                Task { @MainActor [weak self] in
                    self?.states[task] = .downloading(progress: progress)
                }
            }

            dlTask.resume()
        }
    }

    // MARK: - Load

    private func load(_ task: MLTask, from url: URL? = nil) async {
        await MainActor.run { states[task] = .loading }

        let modelPath: URL
        if let url {
            modelPath = url
        } else if let cached = cachedModelURL(for: task,
                                               downloadURL: task.modelDownloadURL) {
            modelPath = cached
        } else {
            await MainActor.run { states[task] = .failed("Model file not found on disk") }
            return
        }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            let compiled = try await MLModel.compileModel(at: modelPath)
            let model    = try MLModel(contentsOf: compiled, configuration: config)
            await MainActor.run {
                loadedModels[task] = model
                states[task] = .ready
            }
        } catch {
            await MainActor.run { states[task] = .failed(error.localizedDescription) }
        }
    }

    // MARK: - Helpers

    /// Returns the on-disk URL for a previously downloaded model, or nil if not present.
    private func cachedModelURL(for task: MLTask, downloadURL: URL?) -> URL? {
        guard let downloadURL else { return nil }

        if downloadURL.pathExtension == "zip" {
            // After extraction the .mlpackage folder lands directly in modelsDirectory.
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: modelsDirectory, includingPropertiesForKeys: nil)) ?? []
            return contents.first { $0.pathExtension == "mlpackage" || $0.pathExtension == "mlmodel" }
        } else {
            let dest = modelsDirectory.appendingPathComponent(downloadURL.lastPathComponent)
            return FileManager.default.fileExists(atPath: dest.path) ? dest : nil
        }
    }
}
