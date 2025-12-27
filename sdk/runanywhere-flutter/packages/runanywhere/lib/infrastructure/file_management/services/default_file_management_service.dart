import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:runanywhere/infrastructure/file_management/protocol/file_management_error.dart';
import 'package:runanywhere/infrastructure/file_management/protocol/file_management_protocol.dart';

/// Default implementation of FileManagementProtocol using dart:io
/// Provides platform-agnostic file operations
/// Matches iOS FileOperationsUtilities functionality
class DefaultFileManagementService implements FileManagementProtocol {
  // MARK: - Directory Access

  @override
  Future<String> getDocumentsDirectory() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      return directory.path;
    } catch (e) {
      throw FileManagementError(
        'Unable to access documents directory: $e',
        FileManagementErrorType.accessDenied,
      );
    }
  }

  @override
  Future<String> getCachesDirectory() async {
    try {
      // path_provider doesn't have getApplicationCacheDirectory
      // Use temp directory as cache location
      final tempDir = Directory.systemTemp;
      final cacheDir = Directory(path.join(tempDir.path, 'cache'));
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      return cacheDir.path;
    } catch (e) {
      throw FileManagementError(
        'Unable to access caches directory: $e',
        FileManagementErrorType.accessDenied,
      );
    }
  }

  @override
  Future<String> getTemporaryDirectory() async {
    try {
      final directory = Directory.systemTemp;
      return directory.path;
    } catch (e) {
      throw FileManagementError(
        'Unable to access temporary directory: $e',
        FileManagementErrorType.accessDenied,
      );
    }
  }

  // MARK: - File Existence

  @override
  bool exists(String filePath) {
    try {
      return File(filePath).existsSync() || Directory(filePath).existsSync();
    } catch (e) {
      return false;
    }
  }

  @override
  Map<String, bool> existsWithType(String filePath) {
    try {
      final file = File(filePath);
      final directory = Directory(filePath);

      final fileExists = file.existsSync();
      final dirExists = directory.existsSync();
      final exists = fileExists || dirExists;
      final isDirectory = dirExists;

      return {
        'exists': exists,
        'isDirectory': isDirectory,
      };
    } catch (e) {
      return {
        'exists': false,
        'isDirectory': false,
      };
    }
  }

  @override
  bool isNonEmptyDirectory(String dirPath) {
    try {
      final directory = Directory(dirPath);
      if (!directory.existsSync()) return false;

      final contents = directory.listSync();
      return contents.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // MARK: - Directory Contents

  @override
  Future<List<String>> contentsOfDirectory(String dirPath) async {
    try {
      final directory = Directory(dirPath);
      if (!await directory.exists()) {
        throw FileManagementError.directoryNotFound(dirPath);
      }

      final contents = await directory.list().toList();
      return contents.map((entity) => entity.path).toList();
    } catch (e) {
      if (e is FileManagementError) rethrow;
      throw FileManagementError(
        'Failed to list directory contents: $e',
        FileManagementErrorType.accessDenied,
      );
    }
  }

  @override
  Future<List<String>> contentsOfDirectoryRecursive(
    String dirPath, {
    bool recursive = false,
  }) async {
    try {
      final directory = Directory(dirPath);
      if (!await directory.exists()) {
        throw FileManagementError.directoryNotFound(dirPath);
      }

      final contents = await directory.list(recursive: recursive).toList();
      return contents.map((entity) => entity.path).toList();
    } catch (e) {
      if (e is FileManagementError) rethrow;
      throw FileManagementError(
        'Failed to list directory contents recursively: $e',
        FileManagementErrorType.accessDenied,
      );
    }
  }

  // MARK: - File Attributes

  @override
  int? fileSize(String filePath) {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;
      return file.lengthSync();
    } catch (e) {
      return null;
    }
  }

  @override
  DateTime? creationDate(String filePath) {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;
      // Note: Dart doesn't provide creation date, using modified date as fallback
      final stat = file.statSync();
      return stat.modified;
    } catch (e) {
      return null;
    }
  }

  @override
  DateTime? modificationDate(String filePath) {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;
      final stat = file.statSync();
      return stat.modified;
    } catch (e) {
      return null;
    }
  }

  // MARK: - Directory Operations

  @override
  Future<void> createDirectory(String dirPath, {bool recursive = true}) async {
    try {
      final directory = Directory(dirPath);
      await directory.create(recursive: recursive);
    } catch (e) {
      throw FileManagementError(
        'Failed to create directory at $dirPath: $e',
        FileManagementErrorType.writeFailed,
      );
    }
  }

  @override
  int calculateDirectorySize(String dirPath) {
    try {
      final directory = Directory(dirPath);
      if (!directory.existsSync()) return 0;

      int totalSize = 0;
      final contents = directory.listSync(recursive: true);
      for (final entity in contents) {
        if (entity is File) {
          try {
            totalSize += entity.lengthSync();
          } catch (e) {
            // Skip files we can't read
            continue;
          }
        }
      }
      return totalSize;
    } catch (e) {
      return 0;
    }
  }

  // MARK: - File/Directory Removal

  @override
  Future<void> removeItem(String itemPath) async {
    try {
      final file = File(itemPath);
      final directory = Directory(itemPath);

      if (await file.exists()) {
        await file.delete();
      } else if (await directory.exists()) {
        await directory.delete(recursive: true);
      } else {
        throw FileManagementError.fileNotFound(itemPath);
      }
    } catch (e) {
      if (e is FileManagementError) rethrow;
      throw FileManagementError.deleteFailed(itemPath, e.toString());
    }
  }

  @override
  Future<bool> removeItemIfExists(String itemPath) async {
    try {
      if (!exists(itemPath)) return false;
      await removeItem(itemPath);
      return true;
    } catch (e) {
      return false;
    }
  }

  // MARK: - File Copy/Move

  @override
  Future<void> copyItem(String sourcePath, String destinationPath) async {
    try {
      final sourceFile = File(sourcePath);
      final sourceDirectory = Directory(sourcePath);

      if (await sourceFile.exists()) {
        await sourceFile.copy(destinationPath);
      } else if (await sourceDirectory.exists()) {
        // For directories, we need to copy recursively
        await _copyDirectory(sourceDirectory, Directory(destinationPath));
      } else {
        throw FileManagementError.fileNotFound(sourcePath);
      }
    } catch (e) {
      if (e is FileManagementError) rethrow;
      throw FileManagementError(
        'Failed to copy from $sourcePath to $destinationPath: $e',
        FileManagementErrorType.writeFailed,
      );
    }
  }

  @override
  Future<void> moveItem(String sourcePath, String destinationPath) async {
    try {
      final sourceFile = File(sourcePath);
      final sourceDirectory = Directory(sourcePath);

      if (await sourceFile.exists()) {
        await sourceFile.rename(destinationPath);
      } else if (await sourceDirectory.exists()) {
        await sourceDirectory.rename(destinationPath);
      } else {
        throw FileManagementError.fileNotFound(sourcePath);
      }
    } catch (e) {
      if (e is FileManagementError) rethrow;
      throw FileManagementError(
        'Failed to move from $sourcePath to $destinationPath: $e',
        FileManagementErrorType.writeFailed,
      );
    }
  }

  // MARK: - File Read/Write

  @override
  Future<List<int>> readFileAsBytes(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw FileManagementError.fileNotFound(filePath);
      }
      return await file.readAsBytes();
    } catch (e) {
      if (e is FileManagementError) rethrow;
      throw FileManagementError(
        'Failed to read file at $filePath: $e',
        FileManagementErrorType.accessDenied,
      );
    }
  }

  @override
  Future<String> readFileAsString(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw FileManagementError.fileNotFound(filePath);
      }
      return await file.readAsString();
    } catch (e) {
      if (e is FileManagementError) rethrow;
      throw FileManagementError(
        'Failed to read file at $filePath: $e',
        FileManagementErrorType.accessDenied,
      );
    }
  }

  @override
  Future<void> writeFileAsBytes(String filePath, List<int> data) async {
    try {
      final file = File(filePath);
      // Create parent directory if it doesn't exist
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
      await file.writeAsBytes(data);
    } catch (e) {
      throw FileManagementError.writeFailed(filePath, e.toString());
    }
  }

  @override
  Future<void> writeFileAsString(String filePath, String content) async {
    try {
      final file = File(filePath);
      // Create parent directory if it doesn't exist
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
      await file.writeAsString(content);
    } catch (e) {
      throw FileManagementError.writeFailed(filePath, e.toString());
    }
  }

  // MARK: - Private Helpers

  /// Recursively copy a directory
  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);

    await for (final entity in source.list(recursive: false)) {
      if (entity is Directory) {
        final newDirectory = Directory(
          path.join(destination.path, path.basename(entity.path)),
        );
        await _copyDirectory(entity, newDirectory);
      } else if (entity is File) {
        await entity.copy(
          path.join(destination.path, path.basename(entity.path)),
        );
      }
    }
  }
}
