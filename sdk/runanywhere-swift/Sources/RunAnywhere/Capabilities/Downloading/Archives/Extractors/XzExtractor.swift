import Foundation

/// XZ archive extractor
public class XzExtractor: BaseArchiveExtractor {

    public init() {
        super.init(category: "XzExtractor")
    }

    public override func extract(archive: URL) async throws -> URL {
        logger.info("Extracting XZ archive: \(archive.lastPathComponent)")

        // Create extraction directory
        let destinationURL = try createExtractionDirectory(for: archive)

        // Determine output filename
        let outputFilename = archive.deletingPathExtension().lastPathComponent
        let outputURL = destinationURL.appendingPathComponent(outputFilename)

        // Use xz command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xz")
        process.arguments = ["-dc", archive.path]

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
                throw DownloadError.extractionFailed("XZ extraction failed: \(errorString)")
            }

            // Write decompressed data
            let decompressedData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            try decompressedData.write(to: outputURL)

            logger.info("Successfully extracted XZ archive to: \(outputURL.path)")
            return outputURL

        } catch {
            // Clean up on failure
            try? FileManager.default.removeItem(at: destinationURL)
            throw DownloadError.extractionFailed("Failed to extract XZ archive: \(error)")
        }
    }
}
