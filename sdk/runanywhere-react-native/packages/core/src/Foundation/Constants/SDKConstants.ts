/**
 * SDK-wide constants.
 *
 * Mirrors `sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Constants/SDKConstants.swift`.
 */

import { Platform } from 'react-native';

/**
 * Backend `DevicePlatform` enum value for the current OS family. The backend
 * auth/device contract only accepts the OS family ("ios", "android", "macos",
 * "windows", "web") — not the binding name ("react_native"), which 422s the
 * SDK auth exchange and leaves every request unauthenticated (telemetry +
 * device registration both fail). Mirrors the Flutter SDK's
 * `SDKConstants.platform` getter and Kotlin's "android".
 */
function osPlatform(): string {
  // Platform.OS is already the OS family the backend expects
  // ("ios"/"android"/"macos"/"windows"/"web"), never the binding name.
  return Platform.OS;
}

export const SDKConstants = {
  /**
   * SDK version - must stay in sync with package.json `version`.
   * Native commons receives this through the Phase 1 init payload.
   * The literal is rewritten by `scripts/release/sync-versions.sh`.
   */
  version: '0.20.0',

  /** SDK name. Mirrors Swift `SDKConstants.name`. */
  name: 'RunAnywhere SDK',

  /** User agent string. Mirrors Swift `SDKConstants.userAgent`. */
  get userAgent(): string {
    return `${this.name}/${this.version} (React Native)`;
  },

  /**
   * SDK platform identifier used by backend auth/device metadata. Must be the
   * OS family (backend `DevicePlatform` enum), not the binding name.
   */
  platform: osPlatform(),

  /**
   * Minimum log level in production.
   * Mirrors Swift `SDKConstants.productionLogLevel`.
   */
  productionLogLevel: 'error',
} as const;
