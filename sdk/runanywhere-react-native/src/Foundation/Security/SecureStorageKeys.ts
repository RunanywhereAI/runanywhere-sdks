/**
 * SecureStorageKeys.ts
 *
 * Keychain/secure storage key constants
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Security/KeychainManager.swift
 */

/**
 * Keys for secure storage (keychain on iOS, keystore on Android)
 *
 * These match the iOS KeychainKey enum values exactly.
 */
export const SecureStorageKeys = {
  // SDK Core
  apiKey: 'com.runanywhere.sdk.apiKey',
  baseURL: 'com.runanywhere.sdk.baseURL',
  environment: 'com.runanywhere.sdk.environment',

  // Device Identity
  deviceUUID: 'com.runanywhere.sdk.device.uuid',

  // Authentication Tokens
  accessToken: 'com.runanywhere.sdk.accessToken',
  refreshToken: 'com.runanywhere.sdk.refreshToken',
  tokenExpiresAt: 'com.runanywhere.sdk.tokenExpiresAt',

  // User/Org Identity
  deviceId: 'com.runanywhere.sdk.deviceId',
  userId: 'com.runanywhere.sdk.userId',
  organizationId: 'com.runanywhere.sdk.organizationId',
} as const;

export type SecureStorageKey = (typeof SecureStorageKeys)[keyof typeof SecureStorageKeys];
