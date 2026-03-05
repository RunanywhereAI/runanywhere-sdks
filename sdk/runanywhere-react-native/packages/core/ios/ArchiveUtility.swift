/**
 * ArchiveUtility.swift
 *
 * Native archive extraction utility for React Native.
 * Uses Apple's native Compression framework for gzip decompression (fast)
 * and pure Swift tar extraction.
 *
 * Mirrors the implementation from:
 * sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Download/Utilities/ArchiveUtility.swift
 *
 * Supports: tar.gz, zip
 * Note: All models should use tar.gz from RunanywhereAI/sherpa-onnx fork for best performance
 */

import Compression
import Foundation

/// Archive extraction errors
public enum ArchiveError: Error, LocalizedError {
    case invalidArchive(String)
    case decompressionFailed(String)
    case extractionFailed(String)
    case unsupportedFormat(String)
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArchive(let msg): return "Invalid archive: \(msg)"
        case .decompressionFailed(let msg): return "Decompression failed: \(msg)"
        case .extractionFailed(let msg): return "Extraction failed: \(msg)"
        case .unsupportedFormat(let msg): return "Unsupported format: \(msg)"
        case .fileNotFound(let msg): return "File not found: \(msg)"
        }
    }
}

/// Utility for handling archive extraction
@objc public final class ArchiveUtility: NSObject {

    // MARK: - Public API

    /// Extract an archive to a destination directory
    /// - Parameters:
    ///   - archivePath: Path to the archive file
    ///   - destinationPath: Destination directory path
    /// - Returns: true if extraction succeeded
    @objc public static func extract(
        archivePath: String,
        to destinationPath: String
    ) -> Bool {
        do {
            try extractArchive(archivePath: archivePath, to: destinationPath)
            return true
        } catch {
            SDKLogger.archive.logError(error, additionalInfo: "Extraction failed")
            return false
        }
    }

    /// Extract an archive to a destination directory (throwing version)
    public static func extractArchive(
        archivePath: String,
        to destinationPath: String,
        progressHandler: ((Double) -> Void)? = nil
    ) throws {
        let archiveURL = URL(fileURLWithPath: archivePath)
        let destinationURL = URL(fileURLWithPath: destinationPath)

        // Ensure archive exists
        guard FileManager.default.fileExists(atPath: archivePath) else {
            throw ArchiveError.fileNotFound("Archive not found: \(archivePath)")
        }

        // Detect archive type by magic bytes (more reliable than file extension)
        let archiveType = try detectArchiveTypeByMagicBytes(archivePath)
        SDKLogger.archive.info("Detected archive type: \(archiveType) for: \(archivePath)")

        switch archiveType {
        case .gzip:
            try extractTarGz(from: archiveURL, to: destinationURL, progressHandler: progressHandler)
        case .zip:
            try extractZip(from: archiveURL, to: destinationURL, progressHandler: progressHandler)
        case .bzip2:
            throw ArchiveError.unsupportedFormat("tar.bz2 not supported. Use tar.gz from RunanywhereAI/sherpa-onnx fork.")
        case .xz:
            throw ArchiveError.unsupportedFormat("tar.xz not supported. Use tar.gz from RunanywhereAI/sherpa-onnx fork.")
        case .unknown:
            // Fallback to file extension check
            let lowercased = archivePath.lowercased()
            if lowercased.hasSuffix(".tar.gz") || lowercased.hasSuffix(".tgz") {
                try extractTarGz(from: archiveURL, to: destinationURL, progressHandler: progressHandler)
            } else if lowercased.hasSuffix(".zip") {
                try extractZip(from: archiveURL, to: destinationURL, progressHandler: progressHandler)
            } else {
                throw ArchiveError.unsupportedFormat("Unknown archive format: \(archivePath)")
            }
        }
    }

    /// Archive type detected by magic bytes
    private enum DetectedArchiveType {
        case gzip
        case zip
        case bzip2
        case xz
        case unknown
    }

    /// Detect archive type by reading magic bytes from file header
    private static func detectArchiveTypeByMagicBytes(_ path: String) throws -> DetectedArchiveType {
        guard let fileHandle = FileHandle(forReadingAtPath: path) else {
            throw ArchiveError.fileNotFound("Cannot open file: \(path)")
        }
        defer { try? fileHandle.close() }

        // Read first 6 bytes for magic number detection
        guard let headerData = try? fileHandle.read(upToCount: 6), headerData.count >= 2 else {
            return .unknown
        }

        // Check for gzip: 0x1f 0x8b
        if headerData[0] == 0x1f && headerData[1] == 0x8b {
            return .gzip
        }

        // Check for zip: 0x50 0x4b 0x03 0x04 ("PK\x03\x04")
        if headerData.count >= 4 &&
           headerData[0] == 0x50 && headerData[1] == 0x4b &&
           headerData[2] == 0x03 && headerData[3] == 0x04 {
            return .zip
        }

        // Check for bzip2: 0x42 0x5a ("BZ")
        if headerData[0] == 0x42 && headerData[1] == 0x5a {
            return .bzip2
        }

        // Check for xz: 0xfd 0x37 0x7a 0x58 0x5a 0x00
        if headerData.count >= 6 &&
           headerData[0] == 0xfd && headerData[1] == 0x37 &&
           headerData[2] == 0x7a && headerData[3] == 0x58 &&
           headerData[4] == 0x5a && headerData[5] == 0x00 {
            return .xz
        }

        return .unknown
    }

    // MARK: - tar.gz Extraction (Native Compression Framework)

    /// Extract a tar.gz archive using Apple's native Compression framework
    private static func extractTarGz(
        from sourceURL: URL,
        to destinationURL: URL,
        progressHandler: ((Double) -> Void)?
    ) throws {
        let overallStart = Date()
        SDKLogger.archive.info("Extracting tar.gz: \(sourceURL.lastPathComponent)")
        progressHandler?(0.0)

        // Step 1: Read compressed data
        let readStart = Date()
        let compressedData = try Data(contentsOf: sourceURL)
        let readTime = Date().timeIntervalSince(readStart)
        SDKLogger.archive.info("Read \(formatBytes(compressedData.count)) in \(String(format: "%.2f", readTime))s")
        progressHandler?(0.05)

        // Step 2: Decompress gzip using NATIVE Compression framework
        let decompressStart = Date()
        SDKLogger.archive.info("Starting native gzip decompression...")
        let tarData = try decompressGzipNative(compressedData)
        let decompressTime = Date().timeIntervalSince(decompressStart)
        SDKLogger.archive.info("Decompressed to \(formatBytes(tarData.count)) in \(String(format: "%.2f", decompressTime))s")
        progressHandler?(0.3)

        // Step 3: Extract tar archive
        let extractStart = Date()
        SDKLogger.archive.info("Extracting tar data...")
        try extractTarData(tarData, to: destinationURL, progressHandler: { progress in
            progressHandler?(0.3 + progress * 0.7)
        })
        let extractTime = Date().timeIntervalSince(extractStart)
        SDKLogger.archive.info("Tar extract completed in \(String(format: "%.2f", extractTime))s")

        let totalTime = Date().timeIntervalSince(overallStart)
        SDKLogger.archive.info("Total extraction time: \(String(format: "%.2f", totalTime))s")
        progressHandler?(1.0)
    }

    /// Decompress gzip data using Apple's native Compression framework
    private static func decompressGzipNative(_ compressedData: Data) throws -> Data {
        // Gzip header validation
        guard compressedData.count >= 10 else {
            throw ArchiveError.invalidArchive("Gzip data too short")
        }

        guard compressedData[0] == 0x1f && compressedData[1] == 0x8b else {
            throw ArchiveError.invalidArchive("Invalid gzip magic number")
        }

        guard compressedData[2] == 8 else {
            throw ArchiveError.invalidArchive("Unsupported gzip compression method")
        }

        let flags = compressedData[3]
        var headerSize = 10

        // Handle optional fields
        if (flags & 0x04) != 0 { // FEXTRA
            guard compressedData.count > headerSize + 2 else {
                throw ArchiveError.invalidArchive("Truncated gzip header (FEXTRA)")
            }
            let extraLen = Int(compressedData[headerSize]) | (Int(compressedData[headerSize + 1]) << 8)
            headerSize += 2 + extraLen
        }

        if (flags & 0x08) != 0 { // FNAME
            while headerSize < compressedData.count && compressedData[headerSize] != 0 {
                headerSize += 1
            }
            headerSize += 1
        }

        if (flags & 0x10) != 0 { // FCOMMENT
            while headerSize < compressedData.count && compressedData[headerSize] != 0 {
                headerSize += 1
            }
            headerSize += 1
        }

        if (flags & 0x02) != 0 { // FHCRC
            headerSize += 2
        }

        // Extract raw deflate stream (skip header and 8-byte trailer)
        guard compressedData.count > headerSize + 8 else {
            throw ArchiveError.invalidArchive("Invalid gzip structure")
        }
        let deflateData = compressedData.subdata(in: headerSize..<(compressedData.count - 8))

        // Use native Compression framework to decompress
        // Start with a reasonable estimate (model files typically compress 3-5x)
        var destinationBufferSize = deflateData.count * 10
        var decompressedData = Data(count: destinationBufferSize)

        let decompressedSize = deflateData.withUnsafeBytes { (srcPtr: UnsafeRawBufferPointer) -> Int in
            guard let sourceAddress = srcPtr.baseAddress else { return 0 }

            return decompressedData.withUnsafeMutableBytes { (destPtr: UnsafeMutableRawBufferPointer) -> Int in
                guard let destAddress = destPtr.baseAddress else { return 0 }

                return compression_decode_buffer(
                    destAddress.assumingMemoryBound(to: UInt8.self),
                    destinationBufferSize,
                    sourceAddress.assumingMemoryBound(to: UInt8.self),
                    deflateData.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        // If buffer was too small, try again with a larger buffer
        if decompressedSize == 0 || decompressedSize == destinationBufferSize {
            destinationBufferSize = deflateData.count * 30
            decompressedData = Data(count: destinationBufferSize)

            let retrySize = deflateData.withUnsafeBytes { (srcPtr: UnsafeRawBufferPointer) -> Int in
                guard let sourceAddress = srcPtr.baseAddress else { return 0 }

                return decompressedData.withUnsafeMutableBytes { (destPtr: UnsafeMutableRawBufferPointer) -> Int in
                    guard let destAddress = destPtr.baseAddress else { return 0 }

                    return compression_decode_buffer(
                        destAddress.assumingMemoryBound(to: UInt8.self),
                        destinationBufferSize,
                        sourceAddress.assumingMemoryBound(to: UInt8.self),
                        deflateData.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }

            guard retrySize > 0 && retrySize < destinationBufferSize else {
                throw ArchiveError.decompressionFailed("Native decompression failed - buffer too small or corrupted data")
            }

            decompressedData.count = retrySize
            return decompressedData
        }

        decompressedData.count = decompressedSize
        return decompressedData
    }

    // MARK: - ZIP Extraction (Pure Swift using Foundation)

    private static func extractZip(
        from sourceURL: URL,
        to destinationURL: URL,
        progressHandler: ((Double) -> Void)?
    ) throws {
        SDKLogger.archive.info("Extracting zip: \(sourceURL.lastPathComponent)")
        progressHandler?(0.0)

        // Create destination directory
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        // Read zip file
        guard let archive = try? Data(contentsOf: sourceURL) else {
            throw ArchiveError.fileNotFound("Cannot read zip file: \(sourceURL.path)")
        }

        // Parse and extract ZIP using pure Swift
        var offset = 0
        var fileCount = 0
        let totalSize = archive.count

        while offset < archive.count - 4 {
            // Check for local file header signature (0x04034b50 = PK\x03\x04)
            let sig0 = archive[offset]
            let sig1 = archive[offset + 1]
            let sig2 = archive[offset + 2]
            let sig3 = archive[offset + 3]

            if sig0 == 0x50 && sig1 == 0x4b && sig2 == 0x03 && sig3 == 0x04 {
                // Local file header
                let compressionMethod = UInt16(archive[offset + 8]) | (UInt16(archive[offset + 9]) << 8)
                let compressedSize = UInt32(archive[offset + 18]) |
                    (UInt32(archive[offset + 19]) << 8) |
                    (UInt32(archive[offset + 20]) << 16) |
                    (UInt32(archive[offset + 21]) << 24)
                let uncompressedSize = UInt32(archive[offset + 22]) |
                    (UInt32(archive[offset + 23]) << 8) |
                    (UInt32(archive[offset + 24]) << 16) |
                    (UInt32(archive[offset + 25]) << 24)
                let fileNameLength = UInt16(archive[offset + 26]) | (UInt16(archive[offset + 27]) << 8)
                let extraFieldLength = UInt16(archive[offset + 28]) | (UInt16(archive[offset + 29]) << 8)

                let headerEnd = offset + 30
                let fileNameData = archive.subdata(in: headerEnd..<(headerEnd + Int(fileNameLength)))
                let fileName = String(data: fileNameData, encoding: .utf8) ?? ""

                let dataStart = headerEnd + Int(fileNameLength) + Int(extraFieldLength)
                let dataEnd = dataStart + Int(compressedSize)

                let filePath = destinationURL.appendingPathComponent(fileName)

                if fileName.hasSuffix("/") {
                    // Directory
                    try FileManager.default.createDirectory(at: filePath, withIntermediateDirectories: true)
                } else if !fileName.isEmpty && !fileName.hasPrefix("__MACOSX") {
                    // File
                    try FileManager.default.createDirectory(at: filePath.deletingLastPathComponent(), withIntermediateDirectories: true)

                    if compressionMethod == 0 {
                        // Stored (no compression)
                        let fileData = archive.subdata(in: dataStart..<dataEnd)
                        try fileData.write(to: filePath)
                    } else if compressionMethod == 8 {
                        // Deflate compression - use native decompression
                        let compressedData = archive.subdata(in: dataStart..<dataEnd)
                        if let decompressed = decompressDeflateDataForZip(compressedData, uncompressedSize: Int(uncompressedSize)) {
                            try decompressed.write(to: filePath)
                        } else {
                            SDKLogger.archive.warning("Failed to decompress \(fileName)")
                        }
                    } else {
                        SDKLogger.archive.warning("Unsupported compression method \(compressionMethod) for \(fileName)")
                    }

                    fileCount += 1
                }

                offset = dataEnd
                progressHandler?(Double(offset) / Double(totalSize))
            } else if sig0 == 0x50 && sig1 == 0x4b && sig2 == 0x01 && sig3 == 0x02 {
                // Central directory - we're done with files
                break
            } else if sig0 == 0x50 && sig1 == 0x4b && sig2 == 0x05 && sig3 == 0x06 {
                // End of central directory
                break
            } else {
                offset += 1
            }
        }

        SDKLogger.archive.info("Extracted \(fileCount) files from zip")
        progressHandler?(1.0)
    }

    /// Decompress deflate data for ZIP files
    private static func decompressDeflateDataForZip(_ data: Data, uncompressedSize: Int) -> Data? {
        var destinationBufferSize = max(uncompressedSize, data.count * 4)
        var decompressedData = Data(count: destinationBufferSize)

        let decompressedSize = data.withUnsafeBytes { (srcPtr: UnsafeRawBufferPointer) -> Int in
            guard let sourceAddress = srcPtr.baseAddress else { return 0 }

            return decompressedData.withUnsafeMutableBytes { (destPtr: UnsafeMutableRawBufferPointer) -> Int in
                guard let destAddress = destPtr.baseAddress else { return 0 }

                // Use COMPRESSION_ZLIB for raw deflate
                return compression_decode_buffer(
                    destAddress.assumingMemoryBound(to: UInt8.self),
                    destinationBufferSize,
                    sourceAddress.assumingMemoryBound(to: UInt8.self),
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard decompressedSize > 0 else { return nil }
        decompressedData.count = decompressedSize
        return decompressedData
    }

    // MARK: - TAR Extraction (Pure Swift)

    /// Extract tar data to destination directory
    private static func extractTarData(
        _ tarData: Data,
        to destinationURL: URL,
        progressHandler: ((Double) -> Void)?
    ) throws {
        // Create destination directory
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        var offset = 0
        let totalSize = tarData.count
        var fileCount = 0

        while offset + 512 <= tarData.count {
            // Read tar header (512 bytes)
            let headerData = tarData.subdata(in: offset..<(offset + 512))

            // Check for end of archive (two consecutive zero blocks)
            if headerData.allSatisfy({ $0 == 0 }) {
                break
            }

            // Parse header
            let nameData = headerData.subdata(in: 0..<100)
            let sizeData = headerData.subdata(in: 124..<136)
            let typeFlag = headerData[156]
            let prefixData = headerData.subdata(in: 345..<500)

            // Get file name
            let name = extractNullTerminatedString(from: nameData)
            let prefix = extractNullTerminatedString(from: prefixData)
            let fullName = prefix.isEmpty ? name : "\(prefix)/\(name)"

            // Skip if name is empty or is macOS resource fork
            guard !fullName.isEmpty, !fullName.hasPrefix("._") else {
                offset += 512
                continue
            }

            // Parse file size (octal)
            let sizeString = extractNullTerminatedString(from: sizeData).trimmingCharacters(in: .whitespaces)
            let fileSize = Int(sizeString, radix: 8) ?? 0

            offset += 512 // Move past header

            let filePath = destinationURL.appendingPathComponent(fullName)

            // Handle different entry types
            if typeFlag == 0x35 || (typeFlag == 0x30 && fullName.hasSuffix("/")) { // Directory
                try FileManager.default.createDirectory(at: filePath, withIntermediateDirectories: true)
            } else if typeFlag == 0x30 || typeFlag == 0 { // Regular file
                // Ensure parent directory exists
                try FileManager.default.createDirectory(at: filePath.deletingLastPathComponent(), withIntermediateDirectories: true)

                // Extract file data
                if fileSize > 0 && offset + fileSize <= tarData.count {
                    let fileData = tarData.subdata(in: offset..<(offset + fileSize))
                    try fileData.write(to: filePath)
                } else {
                    // Create empty file
                    FileManager.default.createFile(atPath: filePath.path, contents: nil)
                }
                fileCount += 1
            } else if typeFlag == 0x32 { // Symbolic link
                let linkName = extractNullTerminatedString(from: headerData.subdata(in: 157..<257))
                if !linkName.isEmpty {
                    try FileManager.default.createDirectory(at: filePath.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? FileManager.default.createSymbolicLink(atPath: filePath.path, withDestinationPath: linkName)
                }
            }

            // Move to next entry (file data + padding to 512-byte boundary)
            offset += fileSize
            let padding = (512 - (fileSize % 512)) % 512
            offset += padding

            // Report progress
            progressHandler?(Double(offset) / Double(totalSize))
        }

        SDKLogger.archive.info("Extracted \(fileCount) files")
    }

    // MARK: - Helpers

    private static func extractNullTerminatedString(from data: Data) -> String {
        if let nullIndex = data.firstIndex(of: 0) {
            return String(data: data.subdata(in: 0..<nullIndex), encoding: .utf8) ?? ""
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

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
