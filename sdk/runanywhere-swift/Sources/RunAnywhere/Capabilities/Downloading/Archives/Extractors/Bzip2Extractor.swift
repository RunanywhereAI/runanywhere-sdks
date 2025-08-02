import Foundation

/// BZIP2 archive extractor
public class Bzip2Extractor: BaseArchiveExtractor {

    public init() {
        super.init(category: "Bzip2Extractor")
    }

    public override func extract(archive: URL) async throws -> URL {
        logger.info("Extracting BZIP2 archive: \(archive.lastPathComponent)")

        // Create extraction directory
        let destinationURL = try createExtractionDirectory(for: archive)

        // Determine output filename
        let outputFilename = archive.deletingPathExtension().lastPathComponent
        let outputURL = destinationURL.appendingPathComponent(outputFilename)

        // Use bunzip2 command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/bunzip2")
        process.arguments = ["-c", archive.path]

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
                throw DownloadError.extractionFailed("BZIP2 extraction failed: \(errorString)")
            }

            // Write decompressed data
            let decompressedData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            try decompressedData.write(to: outputURL)

            logger.info("Successfully extracted BZIP2 archive to: \(outputURL.path)")
            return outputURL

        } catch {
            // Clean up on failure
            try? FileManager.default.removeItem(at: destinationURL)
            throw DownloadError.extractionFailed("Failed to extract BZIP2 archive: \(error)")
        }
    }
}
