/**
 * SecureStorageKeys.ts
 *
 * Keychain/secure storage key constants
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Security/KeychainManager.swift
 */

/**
 * Keys for secure storage (keychain on iOS, keystore on Android).
 * Native commons owns authentication tokens and backend identity state; JS keeps
 * only the Swift KeychainManager keys needed for SDK init and device UUID.
 */
export const SecureStorageKeys = {
  apiKey: 'com.runanywhere.sdk.apiKey',
  baseURL: 'com.runanywhere.sdk.baseURL',
  environment: 'com.runanywhere.sdk.environment',
  deviceUUID: 'com.runanywhere.sdk.device.uuid',
} as const;

export type SecureStorageKey =
  (typeof SecureStorageKeys)[keyof typeof SecureStorageKeys];
