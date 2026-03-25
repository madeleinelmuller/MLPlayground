import Foundation
import CoreML
import Combine

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

    private var downloadTasks: [MLTask: URLSessionDownloadTask] = [:]

    // MARK: - Public

    func prepare(_ task: MLTask) async {
        guard states[task] == .idle || states[task] == .failed("") else { return }

        // SHARP and SpatialLM use custom pipelines (ARKit / on-device algorithms)
        if task == .sharp || task == .spatialLM {
            states[task] = .ready
            return
        }

        guard let downloadURL = task.modelDownloadURL else {
            states[task] = .ready   // model bundled or not needed
            return
        }

        let modelURL = localURL(for: task)
        let fileExists: Bool
        if downloadURL.pathExtension == "zip" {
            let packageName = downloadURL.deletingPathExtension().lastPathComponent
            fileExists = FileManager.default.fileExists(
                atPath: modelsDirectory.appendingPathComponent(packageName).path)
        } else {
            fileExists = FileManager.default.fileExists(atPath: modelURL.path)
        }

        if fileExists {
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
            let localPath = try await downloadFile(task: task, url: url)
            let finalPath: URL

            if url.pathExtension == "zip" {
                finalPath = try unzip(localPath, task: task)
            } else {
                finalPath = localPath
            }

            await load(task, from: finalPath)
        } catch {
            await MainActor.run { states[task] = .failed(error.localizedDescription) }
        }
    }

    private func downloadFile(task: MLTask, url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = URLSession.shared
            let downloadTask = session.downloadTask(with: url) { [weak self] tempURL, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let tempURL = tempURL else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                let destURL = self?.modelsDirectory.appendingPathComponent(url.lastPathComponent) ?? tempURL
                try? FileManager.default.removeItem(at: destURL)
                do {
                    try FileManager.default.moveItem(at: tempURL, to: destURL)
                    continuation.resume(returning: destURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            downloadTask.resume()
            downloadTasks[task] = downloadTask

            // Progress observation
            let obs = downloadTask.observe(\.countOfBytesReceived) { [weak self] dt, _ in
                let total = dt.countOfBytesExpectedToReceive
                let progress = total > 0 ? Double(dt.countOfBytesReceived) / Double(total) : 0
                Task { @MainActor [weak self] in
                    self?.states[task] = .downloading(progress: progress)
                }
            }
            _ = obs  // retain
        }
    }

    private func unzip(_ zipURL: URL, task: MLTask) throws -> URL {
        // Use Process to call unzip (available on macOS/Simulator; on device use ZIPFoundation)
        let destDir = modelsDirectory
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipURL.path, "-d", destDir.path]
        try process.run()
        process.waitUntilExit()
        try? FileManager.default.removeItem(at: zipURL)

        // Find the extracted .mlpackage or .mlmodel
        let contents = try FileManager.default.contentsOfDirectory(at: destDir, includingPropertiesForKeys: nil)
        if let pkg = contents.first(where: { $0.pathExtension == "mlpackage" }) {
            return pkg
        }
        if let mlm = contents.first(where: { $0.pathExtension == "mlmodel" }) {
            return mlm
        }
        throw URLError(.cannotOpenFile)
    }

    // MARK: - Load

    private func load(_ task: MLTask, from url: URL? = nil) async {
        await MainActor.run { states[task] = .loading }
        let modelPath = url ?? localURL(for: task)

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            let compiled = try await MLModel.compileModel(at: modelPath)
            let model = try MLModel(contentsOf: compiled, configuration: config)
            await MainActor.run {
                loadedModels[task] = model
                states[task] = .ready
            }
        } catch {
            await MainActor.run { states[task] = .failed(error.localizedDescription) }
        }
    }

    private func localURL(for task: MLTask) -> URL {
        modelsDirectory.appendingPathComponent("\(task.modelFilename).mlmodel")
    }
}
