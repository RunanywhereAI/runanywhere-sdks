/**
 * Security Module
 *
 * Thin public adapters for native secure storage and device identity.
 * Native commons owns credential, auth token, and device registration state.
 */

export { SecureStorageService } from './SecureStorageService';
export { SecureStorageKeys, type SecureStorageKey } from './SecureStorageKeys';
export {
  SecureStorageError,
  SecureStorageErrorCode,
  isSecureStorageError,
  isItemNotFoundError,
} from './SecureStorageError';
export { DeviceIdentity } from './DeviceIdentity';
