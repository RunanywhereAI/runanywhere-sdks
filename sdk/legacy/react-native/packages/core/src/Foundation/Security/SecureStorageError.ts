/**
 * SecureStorageError.ts
 *
 * Errors for secure storage operations
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Security/KeychainManager.swift
 */

/**
 * Error codes for secure storage operations
 */
export enum SecureStorageErrorCode {
  EncodingError = 'SECURE_STORAGE_ENCODING_ERROR',
  DecodingError = 'SECURE_STORAGE_DECODING_ERROR',
  ItemNotFound = 'SECURE_STORAGE_ITEM_NOT_FOUND',
  StorageError = 'SECURE_STORAGE_STORAGE_ERROR',
  RetrievalError = 'SECURE_STORAGE_RETRIEVAL_ERROR',
  DeletionError = 'SECURE_STORAGE_DELETION_ERROR',
  UnavailableError = 'SECURE_STORAGE_UNAVAILABLE',
}

/**
 * Secure storage error
 *
 * Matches iOS KeychainError enum.
 */
export class SecureStorageError extends Error {
  readonly code: SecureStorageErrorCode;
  readonly underlyingError?: Error;

  constructor(
    code: SecureStorageErrorCode,
    message?: string,
    underlyingError?: Error
  ) {
    const msg = message ?? SecureStorageError.defaultMessage(code);
    super(msg);
    this.name = 'SecureStorageError';
    this.code = code;
    this.underlyingError = underlyingError;
  }

  private static defaultMessage(code: SecureStorageErrorCode): string {
    switch (code) {
      case SecureStorageErrorCode.EncodingError:
        return 'Failed to encode data for secure storage';
      case SecureStorageErrorCode.DecodingError:
        return 'Failed to decode data from secure storage';
      case SecureStorageErrorCode.ItemNotFound:
        return 'Item not found in secure storage';
      case SecureStorageErrorCode.StorageError:
        return 'Failed to store item in secure storage';
      case SecureStorageErrorCode.RetrievalError:
        return 'Failed to retrieve item from secure storage';
      case SecureStorageErrorCode.DeletionError:
        return 'Failed to delete item from secure storage';
      case SecureStorageErrorCode.UnavailableError:
        return 'Secure storage is not available';
    }
  }

  // Factory methods
  static encodingError(underlyingError?: Error): SecureStorageError {
    return new SecureStorageError(
      SecureStorageErrorCode.EncodingError,
      undefined,
      underlyingError
    );
  }

  static decodingError(underlyingError?: Error): SecureStorageError {
    return new SecureStorageError(
      SecureStorageErrorCode.DecodingError,
      undefined,
      underlyingError
    );
  }

  static itemNotFound(key: string): SecureStorageError {
    return new SecureStorageError(
      SecureStorageErrorCode.ItemNotFound,
      `Item not found in secure storage: ${key}`
    );
  }

  static storageError(underlyingError?: Error): SecureStorageError {
    return new SecureStorageError(
      SecureStorageErrorCode.StorageError,
      undefined,
      underlyingError
    );
  }

  static retrievalError(underlyingError?: Error): SecureStorageError {
    return new SecureStorageError(
      SecureStorageErrorCode.RetrievalError,
      undefined,
      underlyingError
    );
  }

  static deletionError(underlyingError?: Error): SecureStorageError {
    return new SecureStorageError(
      SecureStorageErrorCode.DeletionError,
      undefined,
      underlyingError
    );
  }

  static unavailable(): SecureStorageError {
    return new SecureStorageError(SecureStorageErrorCode.UnavailableError);
  }
}

/**
 * Type guard to check if an error is a SecureStorageError
 */
export function isSecureStorageError(
  error: unknown
): error is SecureStorageError {
  return error instanceof SecureStorageError;
}

/**
 * Type guard to check if error is "item not found" specifically
 */
export function isItemNotFoundError(error: unknown): boolean {
  return (
    isSecureStorageError(error) &&
    error.code === SecureStorageErrorCode.ItemNotFound
  );
}
