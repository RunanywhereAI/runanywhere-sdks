import Compression
import Foundation
import SWCompression
import ZIPFoundation

/// Utility for handling archive operations
/// Uses Apple's native Compression framework for gzip (fast) and SWCompression for bzip2/xz (pure Swift)
/// Works on all Apple platforms (iOS, macOS, tvOS, watchOS)
public final class ArchiveUtility {

    private static let logger = SDKLogger(category: "ArchiveUtility")

    private init() {}

    // MARK: - Public Extraction Methods

    /// Extract a tar.bz2 archive to a destination directory
    /// Uses SWCompression for pure Swift bzip2 decompression (slower - Apple doesn't support bzip2 natively)
    /// - Parameters:
    ///   - sourceURL: The URL of the tar.bz2 file to extract
    ///   - destinationURL: The destination directory URL
    ///   - progressHandler: Optional callback for extraction progress (0.0 to 1.0)
    /// - Throws: SDKError if extraction fails
    public static func extractTarBz2Archive(
        from sourceURL: URL,
        to destinationURL: URL,
        progressHandler: ((Double) -> Void)? = nil
    ) throws {
        let overallStart = Date()
        logger.info("🗜️ [EXTRACTION START] tar.bz2 archive: \(sourceURL.lastPathComponent)")
        logger.warning("⚠️ bzip2 uses pure Swift decompression (slower than native gzip)")
        progressHandler?(0.0)

        // Step 1: Read compressed data
        let readStart = Date()
        let compressedData = try Data(contentsOf: sourceURL)
        let readTime = Date().timeIntervalSince(readStart)
        logger.info("📖 [READ] \(formatBytes(compressedData.count)) in \(String(format: "%.2f", readTime))s")
        progressHandler?(0.05)

        // Step 2: Decompress bzip2 using pure Swift (no native support from Apple)
        let decompressStart = Date()
        logger.info("🐢 [DECOMPRESS] Starting pure Swift bzip2 decompression (this may take a while)...")
        let tarData: Data
        do {
            tarData = try BZip2.decompress(data: compressedData)
        } catch {
            logger.error("BZip2 decompression failed: \(error)")
            throw SDKError.download(.extractionFailed, "BZip2 decompression failed: \(error.localizedDescription)", underlying: error)
        }
        let decompressTime = Date().timeIntervalSince(decompressStart)
        logger.info("✅ [DECOMPRESS] \(formatBytes(compressedData.count)) → \(formatBytes(tarData.count)) in \(String(format: "%.2f", decompressTime))s")
        progressHandler?(0.4)

        // Step 3: Extract tar archive
        let extractStart = Date()
        logger.info("📦 [TAR EXTRACT] Extracting files...")
        try extractTarData(tarData, to: destinationURL, progressHandler: { progress in
            progressHandler?(0.4 + progress * 0.6)
        })
        let extractTime = Date().timeIntervalSince(extractStart)
        logger.info("✅ [TAR EXTRACT] Completed in \(String(format: "%.2f", extractTime))s")

        let totalTime = Date().timeIntervalSince(overallStart)
        let timingInfo = """
            read: \(String(format: "%.2f", readTime))s, \
            decompress: \(String(format: "%.2f", decompressTime))s, \
            extract: \(String(format: "%.2f", extractTime))s
            """
        logger.info("🎉 [EXTRACTION COMPLETE] Total: \(String(format: "%.2f", totalTime))s (\(timingInfo))")
        progressHandler?(1.0)
    }

    /// Extract a tar.gz archive to a destination directory
    /// Uses Apple's native Compression framework for fast gzip decompression
    /// - Parameters:
    ///   - sourceURL: The URL of the tar.gz file to extract
    ///   - destinationURL: The destination directory URL
    ///   - progressHandler: Optional callback for extraction progress (0.0 to 1.0)
    /// - Throws: SDKError if extraction fails
    public static func extractTarGzArchive(
        from sourceURL: URL,
        to destinationURL: URL,
        progressHandler: ((Double) -> Void)? = nil
    ) throws {
        let overallStart = Date()
        logger.info("🗜️ [EXTRACTION START] tar.gz archive: \(sourceURL.lastPathComponent)")
        progressHandler?(0.0)

        // Step 1: Read compressed data
        let readStart = Date()
        let compressedData = try Data(contentsOf: sourceURL)
        let readTime = Date().timeIntervalSince(readStart)
        logger.info("📖 [READ] \(formatBytes(compressedData.count)) in \(String(format: "%.2f", readTime))s")
        progressHandler?(0.05)

        // Step 2: Decompress gzip using NATIVE Compression framework (10-20x faster than pure Swift)
        let decompressStart = Date()
        logger.info("⚡ [DECOMPRESS] Starting native gzip decompression...")
        let tarData: Data
        do {
            tarData = try decompressGzipNative(compressedData)
        } catch {
            logger.error("Native gzip decompression failed: \(error), falling back to pure Swift")
            // Fallback to SWCompression if native fails
            do {
                tarData = try GzipArchive.unarchive(archive: compressedData)
            } catch {
                logger.error("Gzip decompression failed: \(error)")
                throw SDKError.download(.extractionFailed, "Gzip decompression failed: \(error.localizedDescription)", underlying: error)
            }
        }
        let decompressTime = Date().timeIntervalSince(decompressStart)
        logger.info("✅ [DECOMPRESS] \(formatBytes(compressedData.count)) → \(formatBytes(tarData.count)) in \(String(format: "%.2f", decompressTime))s")
        progressHandler?(0.3)

        // Step 3: Extract tar archive
        let extractStart = Date()
        logger.info("📦 [TAR EXTRACT] Extracting files...")
        try extractTarData(tarData, to: destinationURL, progressHandler: { progress in
            progressHandler?(0.3 + progress * 0.7)
        })
        let extractTime = Date().timeIntervalSince(extractStart)
        logger.info("✅ [TAR EXTRACT] Completed in \(String(format: "%.2f", extractTime))s")

        let totalTime = Date().timeIntervalSince(overallStart)
        let gzTimingInfo = """
            read: \(String(format: "%.2f", readTime))s, \
            decompress: \(String(format: "%.2f", decompressTime))s, \
            extract: \(String(format: "%.2f", extractTime))s
            """
        logger.info("🎉 [EXTRACTION COMPLETE] Total: \(String(format: "%.2f", totalTime))s (\(gzTimingInfo))")
        progressHandler?(1.0)
    }

    /// Decompress gzip data using Apple's native Compression framework
    /// Uses streaming decompression (compression_stream_process) to avoid huge pre-allocations
    private static func decompressGzipNative(_ compressedData: Data) throws -> Data {
        guard compressedData.count >= 10 else {
            throw SDKError.download(.extractionFailed, "Invalid gzip data: too short")
        }

        guard compressedData[0] == 0x1f && compressedData[1] == 0x8b else {
            throw SDKError.download(.extractionFailed, "Invalid gzip magic number")
        }

        guard compressedData[2] == 8 else {
            throw SDKError.download(.extractionFailed, "Unsupported gzip compression method")
        }

        let flags = compressedData[3]
        var headerSize = 10

        if flags & 0x04 != 0 { // FEXTRA
            guard compressedData.count >= headerSize + 2 else {
                throw SDKError.download(.extractionFailed, "Invalid gzip extra field")
            }
            let extraLen = Int(compressedData[headerSize]) | (Int(compressedData[headerSize + 1]) << 8)
            headerSize += 2 + extraLen
        }

        if flags & 0x08 != 0 { // FNAME
            while headerSize < compressedData.count && compressedData[headerSize] != 0 {
                headerSize += 1
            }
            headerSize += 1
        }

        if flags & 0x10 != 0 { // FCOMMENT
            while headerSize < compressedData.count && compressedData[headerSize] != 0 {
                headerSize += 1
            }
            headerSize += 1
        }

        if flags & 0x02 != 0 { // FHCRC
            headerSize += 2
        }

        guard compressedData.count > headerSize + 8 else {
            throw SDKError.download(.extractionFailed, "Invalid gzip structure")
        }

        let deflateStart = headerSize
        let deflateEnd = compressedData.count - 8

        return try decompressDeflateStreaming(compressedData, range: deflateStart..<deflateEnd)
    }

    /// Decompress raw deflate data using streaming compression_stream_process.
    /// Uses a small 256 KB output buffer instead of pre-allocating compressedSize * N.
    private static func decompressDeflateStreaming(_ data: Data, range: Range<Int>) throws -> Data {
        var stream = compression_stream()
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw SDKError.download(.extractionFailed, "Failed to initialize decompression stream")
        }
        defer { compression_stream_destroy(&stream) }

        let outputChunkSize = 256 * 1024 // 256 KB
        let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: outputChunkSize)
        defer { outputBuffer.deallocate() }

        var result = Data()
        let deflateSize = range.count
        result.reserveCapacity(min(deflateSize * 2, 1024 * 1024 * 1024))

        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else {
                throw SDKError.download(.extractionFailed, "Cannot access compressed data buffer")
            }
            let srcBase = base.advanced(by: range.lowerBound).assumingMemoryBound(to: UInt8.self)

            stream.src_ptr = srcBase
            stream.src_size = deflateSize

            var status: compression_status
            repeat {
                stream.dst_ptr = outputBuffer
                stream.dst_size = outputChunkSize

                status = compression_stream_process(&stream, COMPRESSION_STREAM_FINALIZE)

                let bytesProduced = outputChunkSize - stream.dst_size
                if bytesProduced > 0 {
                    result.append(outputBuffer, count: bytesProduced)
                }
            } while status == COMPRESSION_STATUS_OK

            guard status == COMPRESSION_STATUS_END else {
                throw SDKError.download(.extractionFailed, "Streaming decompression failed (status \(status))")
            }
        }

        return result
    }

    /// Extract a tar.xz archive to a destination directory
    /// Uses SWCompression for pure Swift LZMA/XZ decompression and tar extraction
    /// - Parameters:
    ///   - sourceURL: The URL of the tar.xz file to extract
    ///   - destinationURL: The destination directory URL
    ///   - progressHandler: Optional callback for extraction progress (0.0 to 1.0)
    /// - Throws: SDKError if extraction fails
    public static func extractTarXzArchive(
        from sourceURL: URL,
        to destinationURL: URL,
        progressHandler: ((Double) -> Void)? = nil
    ) throws {
        logger.info("Extracting tar.xz archive: \(sourceURL.lastPathComponent)")
        progressHandler?(0.0)

        // Read compressed data
        let compressedData = try Data(contentsOf: sourceURL)
        logger.debug("Read \(formatBytes(compressedData.count)) from archive")
        progressHandler?(0.1)

        // Step 1: Decompress XZ using SWCompression
        logger.debug("Decompressing XZ...")
        let tarData: Data
        do {
            tarData = try XZArchive.unarchive(archive: compressedData)
        } catch {
            logger.error("XZ decompression failed: \(error)")
            throw SDKError.download(.extractionFailed, "XZ decompression failed: \(error.localizedDescription)", underlying: error)
        }
        logger.debug("Decompressed to \(formatBytes(tarData.count)) of tar data")
        progressHandler?(0.4)

        // Step 2: Extract tar archive using SWCompression
        try extractTarData(tarData, to: destinationURL, progressHandler: { progress in
            // Map tar extraction progress (0.4 to 1.0)
            progressHandler?(0.4 + progress * 0.6)
        })

        logger.info("tar.xz extraction completed to: \(destinationURL.lastPathComponent)")
        progressHandler?(1.0)
    }

    /// Extract a zip archive to a destination directory
    /// Uses ZIPFoundation for zip extraction
    /// - Parameters:
    ///   - sourceURL: The URL of the zip file to extract
    ///   - destinationURL: The destination directory URL
    ///   - progressHandler: Optional callback for extraction progress (0.0 to 1.0)
    /// - Throws: SDKError if extraction fails
    public static func extractZipArchive(
        from sourceURL: URL,
        to destinationURL: URL,
        progressHandler: ((Double) -> Void)? = nil
    ) throws {
        logger.info("Extracting zip archive: \(sourceURL.lastPathComponent)")
        progressHandler?(0.0)

        do {
            let fileManager = FileManager.default

            // Clean up any existing partial extraction to avoid "file already exists" errors
            // This handles cases where a previous extraction was interrupted
            if fileManager.fileExists(atPath: destinationURL.path) {
                logger.info("Removing existing destination directory for clean extraction: \(destinationURL.lastPathComponent)")
                try fileManager.removeItem(at: destinationURL)
            }

            // Ensure destination directory exists
            try fileManager.createDirectory(
                at: destinationURL,
                withIntermediateDirectories: true,
                attributes: nil
            )

            // Use ZIPFoundation to extract
            try fileManager.unzipItem(
                at: sourceURL,
                to: destinationURL,
                skipCRC32: true,
                progress: nil,
                pathEncoding: .utf8
            )

            logger.info("zip extraction completed to: \(destinationURL.lastPathComponent)")
            progressHandler?(1.0)
        } catch {
            logger.error("Zip extraction failed: \(error)")
            throw SDKError.download(.extractionFailed, "Failed to extract zip archive: \(error.localizedDescription)", underlying: error)
        }
    }

    /// Extract any supported archive format based on file extension
    /// - Parameters:
    ///   - sourceURL: The archive file URL
    ///   - destinationURL: The destination directory URL
    ///   - progressHandler: Optional callback for extraction progress (0.0 to 1.0)
    /// - Throws: SDKError if extraction fails or format is unsupported
    public static func extractArchive(
        from sourceURL: URL,
        to destinationURL: URL,
        progressHandler: ((Double) -> Void)? = nil
    ) throws {
        let archiveType = detectArchiveType(from: sourceURL)

        switch archiveType {
        case .tarBz2:
            try extractTarBz2Archive(from: sourceURL, to: destinationURL, progressHandler: progressHandler)
        case .tarGz:
            try extractTarGzArchive(from: sourceURL, to: destinationURL, progressHandler: progressHandler)
        case .tarXz:
            try extractTarXzArchive(from: sourceURL, to: destinationURL, progressHandler: progressHandler)
        case .zip:
            try extractZipArchive(from: sourceURL, to: destinationURL, progressHandler: progressHandler)
        case .unknown:
            throw SDKError.download(.unsupportedArchive, "Unsupported archive format: \(sourceURL.pathExtension)")
        }
    }

    // MARK: - Archive Type Detection

    /// Supported archive types
    public enum ArchiveFormat {
        case tarBz2
        case tarGz
        case tarXz
        case zip
        case unknown
    }

    /// Detect archive type from URL
    public static func detectArchiveType(from url: URL) -> ArchiveFormat {
        let path = url.path.lowercased()

        if path.hasSuffix(".tar.bz2") || path.hasSuffix(".tbz2") || path.hasSuffix(".tbz") {
            return .tarBz2
        } else if path.hasSuffix(".tar.gz") || path.hasSuffix(".tgz") {
            return .tarGz
        } else if path.hasSuffix(".tar.xz") || path.hasSuffix(".txz") {
            return .tarXz
        } else if path.hasSuffix(".zip") {
            return .zip
        }

        return .unknown
    }

    /// Check if a URL points to a tar.bz2 archive
    public static func isTarBz2Archive(_ url: URL) -> Bool {
        detectArchiveType(from: url) == .tarBz2
    }

    /// Check if a URL points to a tar.gz archive
    public static func isTarGzArchive(_ url: URL) -> Bool {
        detectArchiveType(from: url) == .tarGz
    }

    /// Check if a URL points to a zip archive
    public static func isZipArchive(_ url: URL) -> Bool {
        detectArchiveType(from: url) == .zip
    }

    /// Check if a URL points to any supported archive format
    public static func isSupportedArchive(_ url: URL) -> Bool {
        detectArchiveType(from: url) != .unknown
    }

    // MARK: - Zip Creation

    /// Create a zip archive from a source directory
    /// - Parameters:
    ///   - sourceURL: The source directory URL
    ///   - destinationURL: The destination zip file URL
    /// - Throws: SDKError if compression fails
    public static func createZipArchive(
        from sourceURL: URL,
        to destinationURL: URL
    ) throws {
        do {
            try FileManager.default.zipItem(
                at: sourceURL,
                to: destinationURL,
                shouldKeepParent: false,
                compressionMethod: .deflate,
                progress: nil
            )
            logger.info("Created zip archive at: \(destinationURL.lastPathComponent)")
        } catch {
            logger.error("Failed to create zip archive: \(error)")
            throw SDKError.download(.extractionFailed, "Failed to create archive: \(error.localizedDescription)", underlying: error)
        }
    }

    // MARK: - Private Helpers

    /// Extract tar data to destination directory using SWCompression
    private static func extractTarData(
        _ tarData: Data,
        to destinationURL: URL,
        progressHandler: ((Double) -> Void)? = nil
    ) throws {
        // Step 1: Parse tar entries
        let parseStart = Date()
        logger.info("   📋 [TAR PARSE] Parsing tar entries from \(formatBytes(tarData.count))...")

        // Ensure destination directory exists
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        // Parse tar entries using SWCompression
        let entries: [TarEntry]
        do {
            entries = try TarContainer.open(container: tarData)
        } catch {
            logger.error("Tar parsing failed: \(error)")
            throw SDKError.download(.extractionFailed, "Tar parsing failed: \(error.localizedDescription)", underlying: error)
        }
        let parseTime = Date().timeIntervalSince(parseStart)
        logger.info("   ✅ [TAR PARSE] Found \(entries.count) entries in \(String(format: "%.2f", parseTime))s")

        // Step 2: Write files to disk
        let writeStart = Date()
        logger.info("   💾 [FILE WRITE] Writing files to disk...")

        var extractedCount = 0
        var extractedFiles = 0
        var extractedDirs = 0
        var totalBytesWritten: Int64 = 0

        for entry in entries {
            let entryPath = entry.info.name

            // Skip empty names or entries starting with ._ (macOS resource forks)
            guard !entryPath.isEmpty, !entryPath.hasPrefix("._") else {
                continue
            }

            let fullPath = destinationURL.appendingPathComponent(entryPath)

            switch entry.info.type {
            case .directory:
                try FileManager.default.createDirectory(at: fullPath, withIntermediateDirectories: true)
                extractedDirs += 1

            case .regular:
                // Create parent directory if needed
                let parentDir = fullPath.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

                // Write file data
                if let data = entry.data {
                    try data.write(to: fullPath)
                    extractedFiles += 1
                    totalBytesWritten += Int64(data.count)
                }

            case .symbolicLink:
                // Handle symbolic links if needed
                let linkName = entry.info.linkName
                if !linkName.isEmpty {
                    let parentDir = fullPath.deletingLastPathComponent()
                    try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
                    try? FileManager.default.createSymbolicLink(atPath: fullPath.path, withDestinationPath: linkName)
                }

            default:
                // Skip other types (block devices, character devices, etc.)
                break
            }

            extractedCount += 1
            progressHandler?(Double(extractedCount) / Double(entries.count))
        }

        let writeTime = Date().timeIntervalSince(writeStart)
        let bytesStr = formatBytes(Int(totalBytesWritten))
        let timeStr = String(format: "%.2f", writeTime)
        logger.info("   ✅ [FILE WRITE] Wrote \(extractedFiles) files (\(bytesStr)) and \(extractedDirs) dirs in \(timeStr)s")
    }

    /// Format bytes for logging
    private static func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else if bytes < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        } else {
            return String(format: "%.2f GB", Double(bytes) / (1024 * 1024 * 1024))
        }
    }
}

// MARK: - FileManager Extension for Archive Operations

public extension FileManager {

    /// Extract any supported archive format
    /// - Parameters:
    ///   - sourceURL: The archive file URL
    ///   - destinationURL: The destination directory URL
    ///   - progressHandler: Optional callback for extraction progress (0.0 to 1.0)
    /// - Throws: SDKError if extraction fails or format is unsupported
    func extractArchive(
        from sourceURL: URL,
        to destinationURL: URL,
        progressHandler: ((Double) -> Void)? = nil
    ) throws {
        try ArchiveUtility.extractArchive(from: sourceURL, to: destinationURL, progressHandler: progressHandler)
    }
}
