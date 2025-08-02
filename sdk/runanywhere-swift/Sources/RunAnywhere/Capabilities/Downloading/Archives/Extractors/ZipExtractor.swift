import Foundation
import ZIPFoundation

/// ZIP archive extractor
public class ZipExtractor: BaseArchiveExtractor {

    public init() {
        super.init(category: "ZipExtractor")
    }

    public override func extract(archive: URL) async throws -> URL {
        logger.info("Extracting ZIP archive: \(archive.lastPathComponent)")

        // Create extraction directory
        let destinationURL = try createExtractionDirectory(for: archive)

        do {
            // Extract using ZIPFoundation
            try FileManager.default.unzipItem(at: archive, to: destinationURL)

            // Find the main model file
            let modelFile = try findModelFile(in: destinationURL)

            logger.info("Successfully extracted ZIP archive to: \(modelFile.path)")
            return modelFile

        } catch {
            // Clean up on failure
            try? FileManager.default.removeItem(at: destinationURL)
            throw DownloadError.extractionFailed("Failed to extract ZIP archive: \(error)")
        }
    }

    public override func isValidArchive(at url: URL) async -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        // Check if it's a valid ZIP file
        do {
            let fileHandle = try FileHandle(forReadingFrom: url)
            defer { try? fileHandle.close() }

            // Read first 4 bytes for ZIP signature
            let data = fileHandle.readData(ofLength: 4)

            // ZIP file signatures
            let zipSignatures: [[UInt8]] = [
                [0x50, 0x4B, 0x03, 0x04], // Normal ZIP
                [0x50, 0x4B, 0x05, 0x06], // Empty ZIP
                [0x50, 0x4B, 0x07, 0x08]  // Spanned ZIP
            ]

            let bytes = Array(data)
            return zipSignatures.contains { signature in
                bytes.starts(with: signature)
            }

        } catch {
            return false
        }
    }
}
