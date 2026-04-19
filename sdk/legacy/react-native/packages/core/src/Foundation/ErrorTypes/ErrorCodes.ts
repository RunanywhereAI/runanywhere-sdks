/**
 * ErrorCodes.ts
 *
 * Machine-readable error codes for SDK errors.
 * Matches iOS SDK: Foundation/ErrorTypes/ErrorCodes.swift
 *
 * Error code ranges:
 * - 1000-1099: General SDK state errors
 * - 1100-1199: Model loading and validation
 * - 1200-1299: Network and API communication
 * - 1300-1399: File system and storage
 * - 1500-1599: Hardware compatibility
 * - 1600-1699: Authentication and authorization
 * - 1700-1799: Text generation and token limits
 */

export enum ErrorCode {
  // General errors (1000-1099)
  Unknown = 1000,
  InvalidInput = 1001,
  NotInitialized = 1002,
  AlreadyInitialized = 1003,
  OperationCancelled = 1004,

  // Model errors (1100-1199)
  ModelNotFound = 1100,
  ModelLoadFailed = 1101,
  ModelValidationFailed = 1102,
  ModelFormatUnsupported = 1103,
  ModelCorrupted = 1104,
  ModelIncompatible = 1105,

  // Network errors (1200-1299)
  NetworkUnavailable = 1200,
  NetworkTimeout = 1201,
  DownloadFailed = 1202,
  UploadFailed = 1203,
  ApiError = 1204,

  // Storage errors (1300-1399)
  InsufficientStorage = 1300,
  StorageFull = 1301,
  FileNotFound = 1302,
  FileAccessDenied = 1303,
  FileCorrupted = 1304,

  // Hardware errors (1500-1599)
  HardwareUnsupported = 1500,
  HardwareUnavailable = 1501,

  // Authentication errors (1600-1699)
  AuthenticationFailed = 1600,
  AuthenticationExpired = 1601,
  AuthorizationDenied = 1602,
  ApiKeyInvalid = 1603,

  // Generation errors (1700-1799)
  GenerationFailed = 1700,
  GenerationTimeout = 1701,
  TokenLimitExceeded = 1702,
  CostLimitExceeded = 1703,
  ContextTooLong = 1704,
}

/**
 * Get a human-readable message for an error code.
 */
export function getErrorCodeMessage(code: ErrorCode): string {
  switch (code) {
    // General errors
    case ErrorCode.Unknown:
      return 'An unknown error occurred';
    case ErrorCode.InvalidInput:
      return 'Invalid input provided';
    case ErrorCode.NotInitialized:
      return 'SDK not initialized';
    case ErrorCode.AlreadyInitialized:
      return 'SDK already initialized';
    case ErrorCode.OperationCancelled:
      return 'Operation was cancelled';

    // Model errors
    case ErrorCode.ModelNotFound:
      return 'Model not found';
    case ErrorCode.ModelLoadFailed:
      return 'Failed to load model';
    case ErrorCode.ModelValidationFailed:
      return 'Model validation failed';
    case ErrorCode.ModelFormatUnsupported:
      return 'Model format not supported';
    case ErrorCode.ModelCorrupted:
      return 'Model file is corrupted';
    case ErrorCode.ModelIncompatible:
      return 'Model is incompatible with current runtime';

    // Network errors
    case ErrorCode.NetworkUnavailable:
      return 'Network is unavailable';
    case ErrorCode.NetworkTimeout:
      return 'Network request timed out';
    case ErrorCode.DownloadFailed:
      return 'Download failed';
    case ErrorCode.UploadFailed:
      return 'Upload failed';
    case ErrorCode.ApiError:
      return 'API request failed';

    // Storage errors
    case ErrorCode.InsufficientStorage:
      return 'Insufficient storage space';
    case ErrorCode.StorageFull:
      return 'Storage is full';
    case ErrorCode.FileNotFound:
      return 'File not found';
    case ErrorCode.FileAccessDenied:
      return 'File access denied';
    case ErrorCode.FileCorrupted:
      return 'File is corrupted';

    // Hardware errors
    case ErrorCode.HardwareUnsupported:
      return 'Hardware is not supported';
    case ErrorCode.HardwareUnavailable:
      return 'Hardware is unavailable';

    // Authentication errors
    case ErrorCode.AuthenticationFailed:
      return 'Authentication failed';
    case ErrorCode.AuthenticationExpired:
      return 'Authentication has expired';
    case ErrorCode.AuthorizationDenied:
      return 'Authorization denied';
    case ErrorCode.ApiKeyInvalid:
      return 'API key is invalid';

    // Generation errors
    case ErrorCode.GenerationFailed:
      return 'Text generation failed';
    case ErrorCode.GenerationTimeout:
      return 'Text generation timed out';
    case ErrorCode.TokenLimitExceeded:
      return 'Token limit exceeded';
    case ErrorCode.CostLimitExceeded:
      return 'Cost limit exceeded';
    case ErrorCode.ContextTooLong:
      return 'Context is too long';

    default:
      return 'An error occurred';
  }
}
