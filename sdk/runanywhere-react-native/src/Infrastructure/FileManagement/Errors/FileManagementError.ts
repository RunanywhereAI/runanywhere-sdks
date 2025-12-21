/**
 * FileManagementError.ts
 *
 * Typed errors specific to file management operations.
 * Provides detailed error cases for file operations, storage issues, and model file handling.
 * Matches iOS SDK: Infrastructure/FileManagement/Protocol/FileManagementError.swift
 */

import { SDKError } from '../../../Foundation/ErrorTypes/SDKError';
import { ErrorCode } from '../../../Foundation/ErrorTypes/ErrorCodes';

/**
 * Errors that can occur during file management operations
 */
export class FileManagementError extends SDKError {
  // MARK: - Directory Errors

  /**
   * Unable to access or create a directory
   */
  static directoryAccessFailed(path: string, underlying?: Error): FileManagementError {
    const message = underlying
      ? `Failed to access directory at '${path}': ${underlying.message}`
      : `Failed to access directory at '${path}'`;
    return new FileManagementError(ErrorCode.FileAccessDenied, message, {
      underlyingError: underlying,
      details: { path },
    });
  }

  /**
   * Directory not found at specified path
   */
  static directoryNotFound(path: string): FileManagementError {
    return new FileManagementError(ErrorCode.FileNotFound, `Directory not found at '${path}'`, {
      details: { path },
    });
  }

  /**
   * Unable to create directory
   */
  static directoryCreationFailed(path: string, reason: string): FileManagementError {
    return new FileManagementError(
      ErrorCode.FileAccessDenied,
      `Failed to create directory at '${path}': ${reason}`,
      {
        details: { path, reason },
      }
    );
  }

  // MARK: - File Errors

  /**
   * File not found at specified path
   */
  static fileNotFound(path: string): FileManagementError {
    return new FileManagementError(ErrorCode.FileNotFound, `File not found at '${path}'`, {
      details: { path },
    });
  }

  /**
   * Unable to read file
   */
  static fileReadFailed(path: string, underlying?: Error): FileManagementError {
    const message = underlying
      ? `Failed to read file at '${path}': ${underlying.message}`
      : `Failed to read file at '${path}'`;
    return new FileManagementError(ErrorCode.FileAccessDenied, message, {
      underlyingError: underlying,
      details: { path },
    });
  }

  /**
   * Unable to write file
   */
  static fileWriteFailed(path: string, underlying?: Error): FileManagementError {
    const message = underlying
      ? `Failed to write file at '${path}': ${underlying.message}`
      : `Failed to write file at '${path}'`;
    return new FileManagementError(ErrorCode.FileAccessDenied, message, {
      underlyingError: underlying,
      details: { path },
    });
  }

  /**
   * Unable to delete file or directory
   */
  static deleteFailed(path: string, underlying?: Error): FileManagementError {
    const message = underlying
      ? `Failed to delete '${path}': ${underlying.message}`
      : `Failed to delete '${path}'`;
    return new FileManagementError(ErrorCode.FileAccessDenied, message, {
      underlyingError: underlying,
      details: { path },
    });
  }

  /**
   * File operation not permitted
   */
  static permissionDenied(path: string): FileManagementError {
    return new FileManagementError(ErrorCode.FileAccessDenied, `Permission denied for '${path}'`, {
      details: { path },
    });
  }

  // MARK: - Model Storage Errors

  /**
   * Model file not found
   */
  static modelNotFound(modelId: string): FileManagementError {
    return new FileManagementError(ErrorCode.ModelNotFound, `Model '${modelId}' not found in storage`, {
      details: { modelId },
    });
  }

  /**
   * Model folder not accessible
   */
  static modelFolderAccessFailed(modelId: string, underlying?: Error): FileManagementError {
    const message = underlying
      ? `Failed to access model folder for '${modelId}': ${underlying.message}`
      : `Failed to access model folder for '${modelId}'`;
    return new FileManagementError(ErrorCode.FileAccessDenied, message, {
      underlyingError: underlying,
      details: { modelId },
    });
  }

  /**
   * Invalid model format
   */
  static invalidModelFormat(expected: string, received: string): FileManagementError {
    return new FileManagementError(
      ErrorCode.ModelFormatUnsupported,
      `Invalid model format. Expected '${expected}', received '${received}'`,
      {
        details: { expected, received },
      }
    );
  }

  /**
   * Model storage corrupted
   */
  static modelStorageCorrupted(modelId: string, reason: string): FileManagementError {
    return new FileManagementError(
      ErrorCode.ModelCorrupted,
      `Model storage for '${modelId}' is corrupted: ${reason}`,
      {
        details: { modelId, reason },
      }
    );
  }

  // MARK: - Storage Space Errors

  /**
   * Insufficient storage space
   */
  static insufficientSpace(required: number, available: number): FileManagementError {
    const requiredMB = (required / 1024 / 1024).toFixed(2);
    const availableMB = (available / 1024 / 1024).toFixed(2);
    return new FileManagementError(
      ErrorCode.InsufficientStorage,
      `Insufficient storage space. Required: ${requiredMB} MB, Available: ${availableMB} MB`,
      {
        details: { required, available },
      }
    );
  }

  /**
   * Storage full
   */
  static storageFull(): FileManagementError {
    return new FileManagementError(ErrorCode.StorageFull, 'Device storage is full');
  }

  /**
   * Unable to determine available space
   */
  static storageInfoUnavailable(reason: string): FileManagementError {
    return new FileManagementError(
      ErrorCode.FileAccessDenied,
      `Unable to determine storage information: ${reason}`,
      {
        details: { reason },
      }
    );
  }

  // MARK: - Cache Errors

  /**
   * Cache key not found
   */
  static cacheKeyNotFound(key: string): FileManagementError {
    return new FileManagementError(ErrorCode.FileNotFound, `Cache entry not found for key '${key}'`, {
      details: { key },
    });
  }

  /**
   * Cache write failed
   */
  static cacheWriteFailed(key: string, underlying?: Error): FileManagementError {
    const message = underlying
      ? `Failed to write cache for key '${key}': ${underlying.message}`
      : `Failed to write cache for key '${key}'`;
    return new FileManagementError(ErrorCode.FileAccessDenied, message, {
      underlyingError: underlying,
      details: { key },
    });
  }

  /**
   * Cache read failed
   */
  static cacheReadFailed(key: string, underlying?: Error): FileManagementError {
    const message = underlying
      ? `Failed to read cache for key '${key}': ${underlying.message}`
      : `Failed to read cache for key '${key}'`;
    return new FileManagementError(ErrorCode.FileAccessDenied, message, {
      underlyingError: underlying,
      details: { key },
    });
  }

  // MARK: - Download Errors

  /**
   * Download folder not accessible
   */
  static downloadFolderAccessFailed(underlying?: Error): FileManagementError {
    const message = underlying
      ? `Failed to access download folder: ${underlying.message}`
      : 'Failed to access download folder';
    return new FileManagementError(ErrorCode.FileAccessDenied, message, {
      underlyingError: underlying,
    });
  }

  /**
   * Temporary file creation failed
   */
  static tempFileCreationFailed(reason: string): FileManagementError {
    return new FileManagementError(
      ErrorCode.FileAccessDenied,
      `Failed to create temporary file: ${reason}`,
      {
        details: { reason },
      }
    );
  }

  /**
   * Move operation failed
   */
  static moveFailed(from: string, to: string, underlying?: Error): FileManagementError {
    const message = underlying
      ? `Failed to move from '${from}' to '${to}': ${underlying.message}`
      : `Failed to move from '${from}' to '${to}'`;
    return new FileManagementError(ErrorCode.FileAccessDenied, message, {
      underlyingError: underlying,
      details: { from, to },
    });
  }

  // MARK: - Validation Errors

  /**
   * Invalid path provided
   */
  static invalidPath(path: string, reason: string): FileManagementError {
    return new FileManagementError(ErrorCode.InvalidInput, `Invalid path '${path}': ${reason}`, {
      details: { path, reason },
    });
  }

  /**
   * Invalid file name
   */
  static invalidFileName(fileName: string, reason: string): FileManagementError {
    return new FileManagementError(
      ErrorCode.InvalidInput,
      `Invalid file name '${fileName}': ${reason}`,
      {
        details: { fileName, reason },
      }
    );
  }

  /**
   * Model validation failed
   */
  static modelValidationFailed(modelId: string, reason: string): FileManagementError {
    return new FileManagementError(
      ErrorCode.ModelValidationFailed,
      `Model validation failed for '${modelId}': ${reason}`,
      {
        details: { modelId, reason },
      }
    );
  }

  // MARK: - Generic Errors

  /**
   * Unknown file system error
   */
  static unknown(underlying: Error): FileManagementError {
    return new FileManagementError(
      ErrorCode.Unknown,
      `File management error: ${underlying.message}`,
      {
        underlyingError: underlying,
      }
    );
  }

  private constructor(
    code: ErrorCode,
    message: string,
    options?: {
      underlyingError?: Error;
      details?: Record<string, unknown>;
    }
  ) {
    super(code, message, options);
    this.name = 'FileManagementError';
    Object.setPrototypeOf(this, FileManagementError.prototype);
  }

  /**
   * Get recovery suggestion for the error
   */
  getRecoverySuggestion(): string {
    switch (this.code) {
      case ErrorCode.FileAccessDenied:
        if (this.message.includes('directory')) {
          return 'Ensure the application has proper file system permissions and the path is valid.';
        }
        if (this.message.includes('read') || this.message.includes('write')) {
          return 'Check file permissions and ensure the file is not corrupted.';
        }
        if (this.message.includes('delete')) {
          return 'Ensure the file is not in use and you have permission to delete it.';
        }
        if (this.message.includes('Permission denied')) {
          return 'Grant the application necessary file system permissions.';
        }
        if (this.message.includes('cache')) {
          return 'Check available storage space and file permissions.';
        }
        if (this.message.includes('download folder')) {
          return 'Ensure the download folder is accessible and not corrupted.';
        }
        if (this.message.includes('temporary file')) {
          return 'Check available storage space and permissions.';
        }
        if (this.message.includes('move')) {
          return 'Ensure both source and destination paths are valid and accessible.';
        }
        if (this.message.includes('storage information')) {
          return 'Restart the application or check file system permissions.';
        }
        return 'Check file permissions and try again.';

      case ErrorCode.FileNotFound:
        if (this.message.includes('Model')) {
          return 'Download the model first or check the model identifier.';
        }
        if (this.message.includes('Cache')) {
          return 'The cache entry may have been cleared or never existed.';
        }
        return 'Verify the file exists at the specified path.';

      case ErrorCode.ModelNotFound:
        return 'Download the model first or check the model identifier.';

      case ErrorCode.ModelFormatUnsupported:
        return "Ensure you're using the correct model format for your framework.";

      case ErrorCode.ModelCorrupted:
        return 'Delete and re-download the model.';

      case ErrorCode.InsufficientStorage:
      case ErrorCode.StorageFull:
        return 'Free up storage space on your device.';

      case ErrorCode.InvalidInput:
        return 'Provide a valid path or file name.';

      case ErrorCode.ModelValidationFailed:
        return 'Ensure the model file is complete and not corrupted.';

      default:
        return 'Try again or contact support if the issue persists.';
    }
  }
}
