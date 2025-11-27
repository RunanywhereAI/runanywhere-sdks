import Foundation
import ZIPFoundation

/// Utility for handling archive operations
public class ArchiveUtility {

    private init() {}

    // MARK: - Tar.bz2 Extraction

    /// Extract a tar.bz2 archive to a destination directory
    /// - Parameters:
    ///   - sourceURL: The URL of the tar.bz2 file to extract
    ///   - destinationURL: The destination directory URL
    /// - Throws: DownloadError if extraction fails
    public static func extractTarBz2Archive(
        from sourceURL: URL,
        to destinationURL: URL
    ) throws {
        // Read compressed data
        let compressedData = try Data(contentsOf: sourceURL)

        // Decompress bz2
        let tarData = try decompressBz2(data: compressedData)

        // Parse and extract tar
        try extractTar(data: tarData, to: destinationURL)
    }

    /// Decompress bz2 data
    private static func decompressBz2(data: Data) throws -> Data {
        // For bz2, Compression framework doesn't directly support it
        // Use shell command on macOS or fallback to manual decompression
        #if os(macOS)
        // On macOS, use bunzip2 command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/bunzip2")
        process.arguments = ["-c", "-k"]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe

        try process.run()
        inputPipe.fileHandleForWriting.write(data)
        inputPipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        let decompressedData = outputPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0, !decompressedData.isEmpty else {
            throw DownloadError.extractionFailed("bz2 decompression failed")
        }

        return decompressedData
        #else
        // On iOS, use manual bz2 decompression
        return try decompressBz2Manually(data: data)
        #endif
    }

    /// Manual bz2 decompression for iOS (using BZ2 header detection and raw decompression)
    private static func decompressBz2Manually(data: Data) throws -> Data {
        // BZ2 files start with "BZh" magic bytes
        guard data.count > 10,
              data[0] == 0x42, // 'B'
              data[1] == 0x5A, // 'Z'
              data[2] == 0x68  // 'h'
        else {
            throw DownloadError.extractionFailed("Invalid bz2 header")
        }

        // For iOS, we'll need to link against libbz2 or use a Swift package
        // For now, throw an error suggesting the user download pre-extracted models
        throw DownloadError.extractionFailed(
            "tar.bz2 extraction on iOS requires pre-extracted models or a bz2 library. " +
            "Consider using ZIP format or pre-extracted model directories."
        )
    }

    /// Parse and extract tar archive data
    private static func extractTar(data: Data, to destinationURL: URL) throws {
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        var offset = 0
        let blockSize = 512

        while offset + blockSize <= data.count {
            // Read tar header (512 bytes)
            let headerData = data[offset..<(offset + blockSize)]

            // Check for end of archive (two zero blocks)
            if headerData.allSatisfy({ $0 == 0 }) {
                break
            }

            // Parse header
            guard let header = TarHeader(data: headerData) else {
                offset += blockSize
                continue
            }

            offset += blockSize

            // Handle based on type
            let fullPath = destinationURL.appendingPathComponent(header.name)

            switch header.typeflag {
            case "5": // Directory
                try FileManager.default.createDirectory(at: fullPath, withIntermediateDirectories: true)

            case "0", "\0", "": // Regular file
                if header.size > 0 {
                    let fileData = data[offset..<(offset + header.size)]

                    // Create parent directory if needed
                    let parentDir = fullPath.deletingLastPathComponent()
                    try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

                    try fileData.write(to: fullPath)
                }

                // Advance to next block boundary
                let blocks = (header.size + blockSize - 1) / blockSize
                offset += blocks * blockSize

            default:
                // Skip other types (symlinks, etc.)
                let blocks = (header.size + blockSize - 1) / blockSize
                offset += blocks * blockSize
            }
        }
    }

    /// Check if a URL points to a tar.bz2 archive
    public static func isTarBz2Archive(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.hasSuffix(".tar.bz2") || path.hasSuffix(".tbz2")
    }

    /// Extract a zip archive to a destination directory
    /// - Parameters:
    ///   - sourceURL: The URL of the zip file to extract
    ///   - destinationURL: The destination directory URL
    ///   - overwrite: Whether to overwrite existing files
    /// - Throws: DownloadError if extraction fails
    public static func extractZipArchive(
        from sourceURL: URL,
        to destinationURL: URL,
        overwrite: Bool = true
    ) throws {
        do {
            // Ensure destination directory exists
            try FileManager.default.createDirectory(
                at: destinationURL,
                withIntermediateDirectories: true,
                attributes: nil
            )

            // Use ZIPFoundation to extract
            try FileManager.default.unzipItem(
                at: sourceURL,
                to: destinationURL,
                skipCRC32: true,
                progress: nil,
                pathEncoding: .utf8
            )
        } catch {
            throw DownloadError.extractionFailed("Failed to extract archive: \(error.localizedDescription)")
        }
    }

    /// Check if a URL points to a zip archive
    /// - Parameter url: The URL to check
    /// - Returns: true if the URL has a .zip extension
    public static func isZipArchive(_ url: URL) -> Bool {
        return url.pathExtension.lowercased() == "zip"
    }

    /// Create a zip archive from a source directory
    /// - Parameters:
    ///   - sourceURL: The source directory URL
    ///   - destinationURL: The destination zip file URL
    /// - Throws: DownloadError if compression fails
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
        } catch {
            throw DownloadError.extractionFailed("Failed to create archive: \(error.localizedDescription)")
        }
    }
}

// MARK: - Tar Header Parsing

/// Simple tar header parser
private struct TarHeader {
    let name: String
    let size: Int
    let typeflag: String

    init?(data: Data) {
        guard data.count >= 512 else { return nil }

        // Name: bytes 0-99
        let nameData = data[0..<100]
        guard let name = String(data: nameData, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0")) else {
            return nil
        }

        // Skip empty headers
        if name.isEmpty {
            return nil
        }

        self.name = name

        // Size: bytes 124-135 (octal string)
        let sizeData = data[124..<136]
        if let sizeStr = String(data: sizeData, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: " \0")),
           let size = Int(sizeStr, radix: 8) {
            self.size = size
        } else {
            self.size = 0
        }

        // Typeflag: byte 156
        let typeflagByte = data[156]
        self.typeflag = String(UnicodeScalar(typeflagByte))
    }
}

// MARK: - FileManager Extension for Archive Operations
public extension FileManager {

    /// Extract any supported archive format
    /// - Parameters:
    ///   - sourceURL: The archive file URL
    ///   - destinationURL: The destination directory URL
    /// - Throws: DownloadError if extraction fails or format is unsupported
    func extractArchive(from sourceURL: URL, to destinationURL: URL) throws {
        let path = sourceURL.path.lowercased()

        if path.hasSuffix(".zip") {
            try ArchiveUtility.extractZipArchive(from: sourceURL, to: destinationURL)
        } else if path.hasSuffix(".tar.bz2") || path.hasSuffix(".tbz2") {
            try ArchiveUtility.extractTarBz2Archive(from: sourceURL, to: destinationURL)
        } else {
            let ext = sourceURL.pathExtension
            throw DownloadError.unsupportedArchive(ext)
        }
    }
}
