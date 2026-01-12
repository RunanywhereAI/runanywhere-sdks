/// SDK error codes
/// Matches iOS ErrorCode from Foundation/ErrorTypes/ErrorCodes.swift
enum ErrorCode {
  // General errors (1000-1099)
  unknown(1000),
  invalidInput(1001),
  notInitialized(1002),
  alreadyInitialized(1003),
  operationCancelled(1004),

  // Model errors (1100-1199)
  modelNotFound(1100),
  modelLoadFailed(1101),
  modelValidationFailed(1102),
  modelFormatUnsupported(1103),
  modelCorrupted(1104),
  modelIncompatible(1105),

  // Network errors (1200-1299)
  networkUnavailable(1200),
  networkTimeout(1201),
  downloadFailed(1202),
  uploadFailed(1203),
  apiError(1204),

  // Storage errors (1300-1399)
  insufficientStorage(1300),
  storageFull(1301),
  fileNotFound(1302),
  fileAccessDenied(1303),
  fileCorrupted(1304),

  // Hardware errors (1500-1599)
  hardwareUnsupported(1500),
  hardwareUnavailable(1501),

  // Authentication errors (1600-1699)
  authenticationFailed(1600),
  authenticationExpired(1601),
  authorizationDenied(1602),
  apiKeyInvalid(1603),

  // Generation errors (1700-1799)
  generationFailed(1700),
  generationTimeout(1701),
  tokenLimitExceeded(1702),
  costLimitExceeded(1703),
  contextTooLong(1704);

  final int rawValue;

  const ErrorCode(this.rawValue);

  /// Get user-friendly error message
  String get message {
    switch (this) {
      case ErrorCode.unknown:
        return 'An unknown error occurred';
      case ErrorCode.invalidInput:
        return 'Invalid input provided';
      case ErrorCode.notInitialized:
        return 'SDK not initialized';
      case ErrorCode.alreadyInitialized:
        return 'SDK already initialized';
      case ErrorCode.operationCancelled:
        return 'Operation was cancelled';

      case ErrorCode.modelNotFound:
        return 'Model not found';
      case ErrorCode.modelLoadFailed:
        return 'Failed to load model';
      case ErrorCode.modelValidationFailed:
        return 'Model validation failed';
      case ErrorCode.modelFormatUnsupported:
        return 'Model format not supported';
      case ErrorCode.modelCorrupted:
        return 'Model file is corrupted';
      case ErrorCode.modelIncompatible:
        return 'Model incompatible with device';

      case ErrorCode.networkUnavailable:
        return 'Network unavailable';
      case ErrorCode.networkTimeout:
        return 'Network request timed out';
      case ErrorCode.downloadFailed:
        return 'Download failed';
      case ErrorCode.uploadFailed:
        return 'Upload failed';
      case ErrorCode.apiError:
        return 'API request failed';

      case ErrorCode.insufficientStorage:
        return 'Insufficient storage space';
      case ErrorCode.storageFull:
        return 'Storage is full';
      case ErrorCode.fileNotFound:
        return 'File not found';
      case ErrorCode.fileAccessDenied:
        return 'File access denied';
      case ErrorCode.fileCorrupted:
        return 'File is corrupted';

      case ErrorCode.hardwareUnsupported:
        return 'Hardware not supported';
      case ErrorCode.hardwareUnavailable:
        return 'Hardware unavailable';

      case ErrorCode.authenticationFailed:
        return 'Authentication failed';
      case ErrorCode.authenticationExpired:
        return 'Authentication expired';
      case ErrorCode.authorizationDenied:
        return 'Authorization denied';
      case ErrorCode.apiKeyInvalid:
        return 'Invalid API key';

      case ErrorCode.generationFailed:
        return 'Text generation failed';
      case ErrorCode.generationTimeout:
        return 'Generation timed out';
      case ErrorCode.tokenLimitExceeded:
        return 'Token limit exceeded';
      case ErrorCode.costLimitExceeded:
        return 'Cost limit exceeded';
      case ErrorCode.contextTooLong:
        return 'Context too long';
    }
  }
}
