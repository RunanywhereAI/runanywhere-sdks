import Foundation

/// TAR.BZ2 archive extractor
public class TarBz2Extractor: BaseArchiveExtractor {

    public init() {
        super.init(category: "TarBz2Extractor")
    }

    public override func extract(archive: URL) async throws -> URL {
        logger.info("Extracting TAR.BZ2 archive: \(archive.lastPathComponent)")

        // Create extraction directory
        let destinationURL = try createExtractionDirectory(for: archive)

        // Use tar command with bzip2 decompression
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xjf", archive.path, "-C", destinationURL.path]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw DownloadError.extractionFailed("TAR.BZ2 extraction failed: \(errorString)")
            }

            // Find the main model file
            let modelFile = try findModelFile(in: destinationURL)

            logger.info("Successfully extracted TAR.BZ2 archive to: \(modelFile.path)")
            return modelFile

        } catch {
            // Clean up on failure
            try? FileManager.default.removeItem(at: destinationURL)
            throw DownloadError.extractionFailed("Failed to extract TAR.BZ2 archive: \(error)")
        }
    }
}
