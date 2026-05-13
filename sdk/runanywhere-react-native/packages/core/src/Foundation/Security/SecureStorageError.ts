/**
 * SecureStorageError.ts
 *
 * Secure storage failures are represented by the canonical SDKException
 * throwable. This module keeps the legacy public factory names as thin
 * adapters so the JS layer does not own a second error model.
 */

import {
  SDKException,
  isSDKException,
} from '../Errors';

export const SecureStorageErrorCode = {
  EncodingError: 'SECURE_STORAGE_ENCODING_ERROR',
  DecodingError: 'SECURE_STORAGE_DECODING_ERROR',
  ItemNotFound: 'SECURE_STORAGE_ITEM_NOT_FOUND',
  StorageError: 'SECURE_STORAGE_STORAGE_ERROR',
  RetrievalError: 'SECURE_STORAGE_RETRIEVAL_ERROR',
  DeletionError: 'SECURE_STORAGE_DELETION_ERROR',
  UnavailableError: 'SECURE_STORAGE_UNAVAILABLE',
} as const;

export type SecureStorageErrorCode =
  (typeof SecureStorageErrorCode)[keyof typeof SecureStorageErrorCode];

export type SecureStorageError = SDKException;

function defaultMessage(code: SecureStorageErrorCode): string {
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

function makeSecureStorageError(
  code: SecureStorageErrorCode,
  message?: string,
  underlyingError?: Error
): SDKException {
  return SDKException.storageError(
    `[secure-storage:${code}] ${message ?? defaultMessage(code)}`,
    underlyingError
  );
}

export const SecureStorageError = {
  encodingError(underlyingError?: Error): SDKException {
    return makeSecureStorageError(
      SecureStorageErrorCode.EncodingError,
      undefined,
      underlyingError
    );
  },

  decodingError(underlyingError?: Error): SDKException {
    return makeSecureStorageError(
      SecureStorageErrorCode.DecodingError,
      undefined,
      underlyingError
    );
  },

  itemNotFound(key: string): SDKException {
    return makeSecureStorageError(
      SecureStorageErrorCode.ItemNotFound,
      `Item not found in secure storage: ${key}`
    );
  },

  storageError(underlyingError?: Error): SDKException {
    return makeSecureStorageError(
      SecureStorageErrorCode.StorageError,
      undefined,
      underlyingError
    );
  },

  retrievalError(underlyingError?: Error): SDKException {
    return makeSecureStorageError(
      SecureStorageErrorCode.RetrievalError,
      undefined,
      underlyingError
    );
  },

  deletionError(underlyingError?: Error): SDKException {
    return makeSecureStorageError(
      SecureStorageErrorCode.DeletionError,
      undefined,
      underlyingError
    );
  },

  unavailable(): SDKException {
    return makeSecureStorageError(SecureStorageErrorCode.UnavailableError);
  },
} as const;

export function isSecureStorageError(error: unknown): error is SDKException {
  return (
    isSDKException(error) &&
    error.message.startsWith('[secure-storage:')
  );
}

export function isItemNotFoundError(error: unknown): boolean {
  return (
    isSecureStorageError(error) &&
    error.message.startsWith(
      `[secure-storage:${SecureStorageErrorCode.ItemNotFound}]`
    )
  );
}
