import Foundation
import Compression

/// GZIP archive extractor
public class GzipExtractor: BaseArchiveExtractor {

    public init() {
        super.init(category: "GzipExtractor")
    }

    public override func extract(archive: URL) async throws -> URL {
        logger.info("Extracting GZIP archive: \(archive.lastPathComponent)")

        // Create extraction directory
        let destinationURL = try createExtractionDirectory(for: archive)

        // Determine output filename
        let outputFilename = archive.deletingPathExtension().lastPathComponent
        let outputURL = destinationURL.appendingPathComponent(outputFilename)

        do {
            // Read compressed data
            let compressedData = try Data(contentsOf: archive)

            // Decompress using Compression framework
            guard let decompressedData = decompress(data: compressedData) else {
                throw DownloadError.extractionFailed("Failed to decompress GZIP data")
            }

            // Write decompressed data
            try decompressedData.write(to: outputURL)

            logger.info("Successfully extracted GZIP archive to: \(outputURL.path)")
            return outputURL

        } catch {
            // Clean up on failure
            try? FileManager.default.removeItem(at: destinationURL)
            throw DownloadError.extractionFailed("Failed to extract GZIP archive: \(error)")
        }
    }

    public override func isValidArchive(at url: URL) async -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        // Check GZIP magic number
        do {
            let fileHandle = try FileHandle(forReadingFrom: url)
            defer { try? fileHandle.close() }

            let data = fileHandle.readData(ofLength: 2)
            let bytes = Array(data)

            // GZIP magic number: 0x1f 0x8b
            return bytes.count >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b

        } catch {
            return false
        }
    }

    // MARK: - Private Methods

    private func decompress(data: Data) -> Data? {
        return data.withUnsafeBytes { bytes in
            let buffer = UnsafeRawBufferPointer(bytes)

            return buffer.withMemoryRebound(to: UInt8.self) { bytes in
                let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count * 4)
                defer { destinationBuffer.deallocate() }

                let decompressedSize = compression_decode_buffer(
                    destinationBuffer, data.count * 4,
                    bytes.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )

                guard decompressedSize > 0 else { return nil }

                return Data(bytes: destinationBuffer, count: decompressedSize)
            }
        }
    }
}
