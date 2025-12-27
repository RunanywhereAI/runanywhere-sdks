/// File management error types
/// Matches iOS FileManagementError from Infrastructure/FileManagement/Protocol/FileManagementError.swift
class FileManagementError implements Exception {
  final String message;
  final FileManagementErrorType type;

  FileManagementError(this.message, this.type);

  factory FileManagementError.directoryNotFound(String path) {
    return FileManagementError(
      'Directory not found: $path',
      FileManagementErrorType.directoryNotFound,
    );
  }

  factory FileManagementError.fileNotFound(String path) {
    return FileManagementError(
      'File not found: $path',
      FileManagementErrorType.fileNotFound,
    );
  }

  factory FileManagementError.accessDenied(String path) {
    return FileManagementError(
      'Access denied: $path',
      FileManagementErrorType.accessDenied,
    );
  }

  factory FileManagementError.insufficientSpace(int required, int available) {
    return FileManagementError(
      'Insufficient space: $required bytes required, $available available',
      FileManagementErrorType.insufficientSpace,
    );
  }

  factory FileManagementError.writeFailed(String path, String reason) {
    return FileManagementError(
      'Write failed to $path: $reason',
      FileManagementErrorType.writeFailed,
    );
  }

  factory FileManagementError.deleteFailed(String path, String reason) {
    return FileManagementError(
      'Delete failed for $path: $reason',
      FileManagementErrorType.deleteFailed,
    );
  }

  @override
  String toString() => 'FileManagementError($type): $message';
}

/// File management error types
enum FileManagementErrorType {
  directoryNotFound,
  fileNotFound,
  accessDenied,
  insufficientSpace,
  writeFailed,
  deleteFailed,
}
