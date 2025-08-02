import Foundation

/// TAR.GZ archive extractor
public class TarGzExtractor: BaseArchiveExtractor {

    public init() {
        super.init(category: "TarGzExtractor")
    }

    public override func extract(archive: URL) async throws -> URL {
        logger.info("Extracting TAR.GZ archive: \(archive.lastPathComponent)")

        // Create extraction directory
        let destinationURL = try createExtractionDirectory(for: archive)

        // Use tar command with gzip decompression
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", archive.path, "-C", destinationURL.path]

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
                throw DownloadError.extractionFailed("TAR.GZ extraction failed: \(errorString)")
            }

            // Find the main model file
            let modelFile = try findModelFile(in: destinationURL)

            logger.info("Successfully extracted TAR.GZ archive to: \(modelFile.path)")
            return modelFile

        } catch {
            // Clean up on failure
            try? FileManager.default.removeItem(at: destinationURL)
            throw DownloadError.extractionFailed("Failed to extract TAR.GZ archive: \(error)")
        }
    }

    public override func isValidArchive(at url: URL) async -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        // Check if it's a valid TAR.GZ file
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-tzf", url.path]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
