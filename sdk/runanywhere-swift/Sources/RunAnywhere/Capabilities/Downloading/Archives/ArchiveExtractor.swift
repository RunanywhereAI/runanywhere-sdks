import Foundation

/// Protocol for archive extraction
public protocol ArchiveExtractor {
    /// Extract the archive to a destination directory
    func extract(archive: URL) async throws -> URL

    /// Verify if the archive is valid
    func isValidArchive(at url: URL) async -> Bool
}

/// Base implementation for archive extractors
public class BaseArchiveExtractor: ArchiveExtractor {

    let logger: SDKLogger

    init(category: String) {
        self.logger = SDKLogger(category: category)
    }

    public func extract(archive: URL) async throws -> URL {
        fatalError("Subclasses must implement extract(archive:)")
    }

    public func isValidArchive(at url: URL) async -> Bool {
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Helper Methods

    /// Create extraction directory
    func createExtractionDirectory(for archive: URL) throws -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let extractedModelsURL = documentsURL.appendingPathComponent("ExtractedModels", isDirectory: true)

        // Create base directory if needed
        try FileManager.default.createDirectory(at: extractedModelsURL, withIntermediateDirectories: true)

        // Create unique directory for this extraction
        let archiveName = archive.deletingPathExtension().lastPathComponent
        let extractionURL = extractedModelsURL.appendingPathComponent(archiveName, isDirectory: true)

        // Remove existing directory if needed
        if FileManager.default.fileExists(atPath: extractionURL.path) {
            try FileManager.default.removeItem(at: extractionURL)
        }

        try FileManager.default.createDirectory(at: extractionURL, withIntermediateDirectories: true)

        return extractionURL
    }

    /// Find the main model file in extracted contents
    func findModelFile(in directory: URL) throws -> URL {
        let modelExtensions = ["onnx", "tflite", "mlmodel", "mlpackage", "gguf", "bin", "safetensors", "pt", "pth", "h5", "keras"]

        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var modelFiles: [URL] = []

        while let fileURL = enumerator?.nextObject() as? URL {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if resourceValues.isRegularFile == true {
                let fileExtension = fileURL.pathExtension.lowercased()
                if modelExtensions.contains(fileExtension) {
                    modelFiles.append(fileURL)
                }
            }
        }

        // Return the largest model file
        if let largestFile = modelFiles.max(by: { file1, file2 in
            let size1 = (try? FileManager.default.attributesOfItem(atPath: file1.path)[.size] as? Int64) ?? 0
            let size2 = (try? FileManager.default.attributesOfItem(atPath: file2.path)[.size] as? Int64) ?? 0
            return size1 < size2
        }) {
            return largestFile
        }

        throw DownloadError.extractionFailed("No model file found in extracted archive")
    }
}
