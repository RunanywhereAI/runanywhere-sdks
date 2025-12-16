import Foundation

/// Centralized utilities for file operations across the SDK
/// Provides a single source of truth for all file system interactions
public struct FileOperationsUtilities {

    // MARK: - Directory Access

    /// Get the documents directory URL
    /// - Returns: URL to the documents directory
    /// - Throws: SDKError if documents directory is not accessible
    public static func getDocumentsDirectory() throws -> URL {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw RunAnywhereError.storageError("Unable to access documents directory")
        }
        return documentsURL
    }

    /// Get the caches directory URL
    /// - Returns: URL to the caches directory
    /// - Throws: SDKError if caches directory is not accessible
    public static func getCachesDirectory() throws -> URL {
        guard let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw RunAnywhereError.storageError("Unable to access caches directory")
        }
        return cachesURL
    }

    /// Get the temporary directory URL
    /// - Returns: URL to the temporary directory
    public static func getTemporaryDirectory() -> URL {
        return FileManager.default.temporaryDirectory
    }

    // MARK: - File Existence

    /// Check if a file or directory exists at the given path
    /// - Parameter url: The URL to check
    /// - Returns: true if the file or directory exists
    public static func exists(at url: URL) -> Bool {
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Check if a file or directory exists and get whether it's a directory
    /// - Parameter url: The URL to check
    /// - Returns: Tuple of (exists, isDirectory)
    public static func existsWithType(at url: URL) -> (exists: Bool, isDirectory: Bool) {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return (exists, isDirectory.boolValue)
    }

    /// Check if a path is a non-empty directory
    /// - Parameter url: The URL to check
    /// - Returns: true if it's a directory with at least one item
    public static func isNonEmptyDirectory(at url: URL) -> Bool {
        let (exists, isDirectory) = existsWithType(at: url)
        guard exists && isDirectory else { return false }

        if let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path),
           !contents.isEmpty {
            return true
        }
        return false
    }

    // MARK: - Directory Contents

    /// List contents of a directory
    /// - Parameter url: The directory URL
    /// - Returns: Array of URLs for items in the directory
    /// - Throws: Error if directory cannot be read
    public static func contentsOfDirectory(at url: URL) throws -> [URL] {
        return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }

    /// List contents of a directory with specific properties
    /// - Parameters:
    ///   - url: The directory URL
    ///   - properties: Resource keys to include
    /// - Returns: Array of URLs for items in the directory
    /// - Throws: Error if directory cannot be read
    public static func contentsOfDirectory(at url: URL, includingPropertiesForKeys properties: [URLResourceKey]) throws -> [URL] {
        return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: properties)
    }

    /// Enumerate directory contents recursively
    /// - Parameters:
    ///   - url: The directory URL to enumerate
    ///   - properties: Resource keys to fetch for each file
    ///   - options: Enumeration options
    /// - Returns: DirectoryEnumerator or nil if enumeration fails
    public static func enumerateDirectory(
        at url: URL,
        includingPropertiesForKeys properties: [URLResourceKey]? = nil,
        options: FileManager.DirectoryEnumerationOptions = []
    ) -> FileManager.DirectoryEnumerator? {
        return FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: properties,
            options: options
        )
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

    /// Get file attributes
    /// - Parameter url: The file URL
    /// - Returns: Dictionary of file attributes
    /// - Throws: Error if attributes cannot be read
    public static func attributes(at url: URL) throws -> [FileAttributeKey: Any] { // swiftlint:disable:this avoid_any_type
        return try FileManager.default.attributesOfItem(atPath: url.path)
    }

    /// Get the creation date of a file
    /// - Parameter url: The file URL
    /// - Returns: Creation date or nil if unavailable
    public static func creationDate(at url: URL) -> Date? {
        return (try? attributes(at: url))?[.creationDate] as? Date
    }

    /// Get the modification date of a file
    /// - Parameter url: The file URL
    /// - Returns: Modification date or nil if unavailable
    public static func modificationDate(at url: URL) -> Date? {
        return (try? attributes(at: url))?[.modificationDate] as? Date
    }

    // MARK: - Directory Operations

    /// Create a directory at the specified URL
    /// - Parameters:
    ///   - url: The URL where to create the directory
    ///   - withIntermediateDirectories: Whether to create intermediate directories
    /// - Throws: Error if directory creation fails
    public static func createDirectory(at url: URL, withIntermediateDirectories: Bool = true) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories, attributes: nil)
    }

    /// Calculate the total size of a directory including all subdirectories
    /// - Parameter url: The directory URL
    /// - Returns: Total size in bytes
    public static func calculateDirectorySize(at url: URL) -> Int64 {
        var totalSize: Int64 = 0

        if let enumerator = enumerateDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }

        return totalSize
    }

    // MARK: - File/Directory Removal

    /// Remove a file or directory at the specified URL
    /// - Parameter url: The URL of the item to remove
    /// - Throws: Error if removal fails
    public static func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    /// Remove a file or directory if it exists
    /// - Parameter url: The URL of the item to remove
    /// - Returns: true if item was removed, false if it didn't exist
    @discardableResult
    public static func removeItemIfExists(at url: URL) -> Bool {
        guard exists(at: url) else { return false }
        do {
            try removeItem(at: url)
            return true
        } catch {
            return false
        }
    }

    // MARK: - File Copy/Move

    /// Copy a file from source to destination
    /// - Parameters:
    ///   - sourceURL: The source file URL
    ///   - destinationURL: The destination file URL
    /// - Throws: Error if copy fails
    public static func copyItem(from sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    /// Move a file from source to destination
    /// - Parameters:
    ///   - sourceURL: The source file URL
    ///   - destinationURL: The destination file URL
    /// - Throws: Error if move fails
    public static func moveItem(from sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }
}
