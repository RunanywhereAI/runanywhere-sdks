// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import Foundation
import CRACommonsCore

/// Downloads and manages model files on-device. Wraps
/// `ra_http_download` (via PlatformAdapter) and `ra_extract_archive_via_adapter`.
///
///     let manager = ModelManager(
///         baseDirectory: URL.documentsDirectory.appending(path: "models"))
///     let path = try await manager.download(
///         modelId: "qwen3-4b",
///         url: URL(string: "https://huggingface.co/.../qwen3-4b.gguf")!)
///     let session = try LLMSession(modelId: "qwen3-4b", modelPath: path.path)
public final class ModelManager: @unchecked Sendable {

    public struct Progress: Sendable {
        public let bytesDownloaded: Int64
        public let totalBytes: Int64
        public var fraction: Double {
            totalBytes > 0 ? Double(bytesDownloaded) / Double(totalBytes) : 0
        }
    }

    public enum Error: Swift.Error {
        case downloadFailed(String)
        case invalidURL(String)
        case extractFailed(String)
        case modelNotFound(String)
    }

    private let fileManager = FileManager.default
    private let baseDirectory: URL

    public init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
        try? fileManager.createDirectory(at: baseDirectory,
                                          withIntermediateDirectories: true)
    }

    /// Returns the on-disk path for `modelId`. Does not verify existence.
    public func path(for modelId: String, fileName: String? = nil) -> URL {
        let dir = baseDirectory.appending(path: modelId)
        if let fileName {
            return dir.appending(path: fileName)
        }
        return dir
    }

    public func isAvailable(modelId: String) -> Bool {
        let dir = path(for: modelId)
        guard let contents = try? fileManager.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return false }
        return !contents.isEmpty
    }

    /// Downloads a model file (or archive) from `url` into the model's
    /// directory. Returns the URL of the downloaded file. If the URL ends
    /// in `.zip`/`.tar`/`.tar.gz`, the content is extracted after download.
    public func download(modelId: String, url: URL,
                         fileName: String? = nil) async throws -> URL {
        let derivedFileName = fileName ?? url.lastPathComponent
        let modelDir = path(for: modelId)
        try fileManager.createDirectory(at: modelDir,
                                         withIntermediateDirectories: true)
        let destUrl = modelDir.appending(path: derivedFileName)

        return try await withCheckedThrowingContinuation { continuation in
            let ctx = CallbackContext { status, resultPath in
                if status == Int32(RA_OK) {
                    if ModelManager.isArchive(path: derivedFileName) {
                        do {
                            try self.extractArchive(archive: destUrl,
                                                      destination: modelDir)
                            let extracted = try self.firstModelFile(in: modelDir,
                                                                     skip: destUrl)
                            continuation.resume(returning: extracted)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    } else {
                        continuation.resume(returning: destUrl)
                    }
                } else {
                    continuation.resume(throwing:
                        Error.downloadFailed("status \(status)"))
                }
                _ = resultPath  // unused — path already known
            }

            let ctxPtr = Unmanaged.passRetained(ctx).toOpaque()

            let rc: Int32 = url.absoluteString.withCString { urlPtr in
                destUrl.path.withCString { destPtr in
                    var outTaskId: UnsafeMutablePointer<CChar>? = nil
                    return ra_http_download(urlPtr, destPtr, nil,
                        { status, path, userData in
                            guard let userData else { return }
                            let ctx = Unmanaged<CallbackContext>
                                .fromOpaque(userData).takeRetainedValue()
                            ctx.onComplete(status, path)
                        },
                        ctxPtr, &outTaskId)
                }
            }

            if rc != Int32(RA_OK) {
                _ = Unmanaged<CallbackContext>.fromOpaque(ctxPtr).takeRetainedValue()
                continuation.resume(throwing:
                    Error.downloadFailed("ra_http_download rc=\(rc)"))
            }
        }
    }

    /// Deletes the model directory and all contents.
    public func delete(modelId: String) throws {
        let dir = path(for: modelId)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
    }

    /// Lists all model IDs currently on disk.
    public func availableModels() -> [String] {
        (try? fileManager.contentsOfDirectory(
            at: baseDirectory, includingPropertiesForKeys: nil)
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?
                    .isDirectory == true }
            .map { $0.lastPathComponent }) ?? []
    }

    // MARK: - Archive extraction

    private static func isArchive(path: String) -> Bool {
        ["zip", "tar", "gz", "tgz"].contains {
            path.lowercased().hasSuffix(".\($0)")
        }
    }

    private func extractArchive(archive: URL, destination: URL) throws {
        let status: Int32 = archive.path.withCString { archivePtr in
            destination.path.withCString { destPtr in
                ra_extract_archive_via_adapter(archivePtr, destPtr, nil, nil)
            }
        }
        if status != Int32(RA_OK) {
            throw Error.extractFailed("ra_extract_archive_via_adapter rc=\(status)")
        }
    }

    private func firstModelFile(in dir: URL, skip: URL) throws -> URL {
        let contents = try fileManager.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)
        for item in contents where item != skip {
            if ModelManager.isModelFile(path: item.path) {
                return item
            }
        }
        throw Error.modelNotFound("no model file found in \(dir.path)")
    }

    private static func isModelFile(path: String) -> Bool {
        ["gguf", "onnx", "bin", "safetensors", "mlmodelc", "pte"].contains {
            path.lowercased().hasSuffix(".\($0)")
        }
    }
}

private final class CallbackContext {
    let onComplete: (Int32, UnsafePointer<CChar>?) -> Void
    init(onComplete: @escaping (Int32, UnsafePointer<CChar>?) -> Void) {
        self.onComplete = onComplete
    }
}
