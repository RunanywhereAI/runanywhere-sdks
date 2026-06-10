import Foundation

/// Centralized utilities for file operations across the SDK
/// Provides a single source of truth for all file system interactions
public struct FileOperationsUtilities {

    // MARK: - File Existence

    /// Check if a file or directory exists and get whether it's a directory
    /// - Parameter url: The URL to check
    /// - Returns: Tuple of (exists, isDirectory)
    public static func existsWithType(at url: URL) -> (exists: Bool, isDirectory: Bool) {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return (exists, isDirectory.boolValue)
    }

    // MARK: - File Attributes

    /// Get the size of a file in bytes
    /// - Parameter url: The file URL
    /// - Returns: File size in bytes, or nil if unavailable
    public static func fileSize(at url: URL) -> Int64? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64
        } catch {
            return nil
        }
    }
}
