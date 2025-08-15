import Foundation
import ZIPFoundation

/// Utility for handling archive operations
public class ArchiveUtility {

    private init() {}

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

// MARK: - FileManager Extension for Archive Operations
public extension FileManager {

    /// Extract any supported archive format
    /// - Parameters:
    ///   - sourceURL: The archive file URL
    ///   - destinationURL: The destination directory URL
    /// - Throws: DownloadError if extraction fails or format is unsupported
    func extractArchive(from sourceURL: URL, to destinationURL: URL) throws {
        let ext = sourceURL.pathExtension.lowercased()

        switch ext {
        case "zip":
            try ArchiveUtility.extractZipArchive(from: sourceURL, to: destinationURL)
        case "tar", "gz", "tgz":
            // Tar archives are not supported on iOS without external libraries
            throw DownloadError.unsupportedArchive("tar/gz archives not supported on iOS")
        default:
            throw DownloadError.unsupportedArchive(ext)
        }
    }
}
