/**
 * Download module exports
 */

// Protocol
export type { DownloadStrategy } from './Protocol/DownloadStrategy';

// Errors
export type { DownloadError } from './Errors';
export {
  DownloadErrorFactory,
  isDownloadError,
  getDownloadErrorDescription,
  isInvalidURLError,
  isNetworkError,
  isTimeoutError,
  isPartialDownloadError,
  isChecksumMismatchError,
  isExtractionFailedError,
  isUnsupportedArchiveError,
  isUnknownError,
  isInvalidResponseError,
  isHTTPError,
  isCancelledError,
  isInsufficientSpaceError,
  isModelNotFoundError,
  isConnectionLostError,
} from './Errors';

// Constants
export { DownloadConstants, type DownloadConstantsType } from './Constants';
