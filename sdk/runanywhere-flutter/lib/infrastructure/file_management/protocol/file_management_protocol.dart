import 'dart:async';

/// Comprehensive file management protocol defining all file system operations
/// Matches iOS FileOperationsUtilities from Infrastructure/FileManagement/Utilities/FileOperationsUtilities.swift
///
/// This protocol extends beyond model-specific operations to include generic file operations
abstract class FileManagementProtocol {
  // MARK: - Directory Access

  /// Get the documents directory path
  /// Returns: Path to the documents directory
  /// Throws: FileManagementError if documents directory is not accessible
  Future<String> getDocumentsDirectory();

  /// Get the caches directory path
  /// Returns: Path to the caches directory
  /// Throws: FileManagementError if caches directory is not accessible
  Future<String> getCachesDirectory();

  /// Get the temporary directory path
  /// Returns: Path to the temporary directory
  Future<String> getTemporaryDirectory();

  // MARK: - File Existence

  /// Check if a file or directory exists at the given path
  /// - Parameter path: The path to check
  /// - Returns: true if the file or directory exists
  bool exists(String path);

  /// Check if a file or directory exists and get whether it's a directory
  /// - Parameter path: The path to check
  /// - Returns: Map with 'exists' and 'isDirectory' keys
  Map<String, bool> existsWithType(String path);

  /// Check if a path is a non-empty directory
  /// - Parameter path: The path to check
  /// - Returns: true if it's a directory with at least one item
  bool isNonEmptyDirectory(String path);

  // MARK: - Directory Contents

  /// List contents of a directory
  /// - Parameter path: The directory path
  /// - Returns: List of paths for items in the directory
  /// - Throws: FileManagementError if directory cannot be read
  Future<List<String>> contentsOfDirectory(String path);

  /// List contents of a directory recursively
  /// - Parameter path: The directory path
  /// - Parameter recursive: Whether to list recursively
  /// - Returns: List of paths for items in the directory
  /// - Throws: FileManagementError if directory cannot be read
  Future<List<String>> contentsOfDirectoryRecursive(
    String path, {
    bool recursive = false,
  });

  // MARK: - File Attributes

  /// Get the size of a file in bytes
  /// - Parameter path: The file path
  /// - Returns: File size in bytes, or null if unavailable
  int? fileSize(String path);

  /// Get the creation date of a file
  /// - Parameter path: The file path
  /// - Returns: Creation date or null if unavailable
  DateTime? creationDate(String path);

  /// Get the modification date of a file
  /// - Parameter path: The file path
  /// - Returns: Modification date or null if unavailable
  DateTime? modificationDate(String path);

  // MARK: - Directory Operations

  /// Create a directory at the specified path
  /// - Parameters:
  ///   - path: The path where to create the directory
  ///   - recursive: Whether to create intermediate directories (default: true)
  /// - Throws: FileManagementError if directory creation fails
  Future<void> createDirectory(String path, {bool recursive = true});

  /// Calculate the total size of a directory including all subdirectories
  /// - Parameter path: The directory path
  /// - Returns: Total size in bytes
  int calculateDirectorySize(String path);

  // MARK: - File/Directory Removal

  /// Remove a file or directory at the specified path
  /// - Parameter path: The path of the item to remove
  /// - Throws: FileManagementError if removal fails
  Future<void> removeItem(String path);

  /// Remove a file or directory if it exists
  /// - Parameter path: The path of the item to remove
  /// - Returns: true if item was removed, false if it didn't exist
  Future<bool> removeItemIfExists(String path);

  // MARK: - File Copy/Move

  /// Copy a file from source to destination
  /// - Parameters:
  ///   - sourcePath: The source file path
  ///   - destinationPath: The destination file path
  /// - Throws: FileManagementError if copy fails
  Future<void> copyItem(String sourcePath, String destinationPath);

  /// Move a file from source to destination
  /// - Parameters:
  ///   - sourcePath: The source file path
  ///   - destinationPath: The destination file path
  /// - Throws: FileManagementError if move fails
  Future<void> moveItem(String sourcePath, String destinationPath);

  // MARK: - File Read/Write

  /// Read file as bytes
  /// - Parameter path: The file path
  /// - Returns: File contents as bytes
  /// - Throws: FileManagementError if read fails
  Future<List<int>> readFileAsBytes(String path);

  /// Read file as string
  /// - Parameter path: The file path
  /// - Returns: File contents as string
  /// - Throws: FileManagementError if read fails
  Future<String> readFileAsString(String path);

  /// Write bytes to file
  /// - Parameters:
  ///   - path: The file path
  ///   - data: The data to write
  /// - Throws: FileManagementError if write fails
  Future<void> writeFileAsBytes(String path, List<int> data);

  /// Write string to file
  /// - Parameters:
  ///   - path: The file path
  ///   - content: The content to write
  /// - Throws: FileManagementError if write fails
  Future<void> writeFileAsString(String path, String content);
}
