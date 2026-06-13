/**
 * SDK-wide constants.
 *
 * Mirrors `sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Constants/SDKConstants.swift`.
 */

export const SDKConstants = {
  /**
   * SDK version - must stay in sync with package.json `version`.
   * Native commons receives this through the Phase 1 init payload.
   * The literal is rewritten by `scripts/release/sync-versions.sh`.
   */
  version: '0.19.13',

  /** SDK name. Mirrors Swift `SDKConstants.name`. */
  name: 'RunAnywhere SDK',

  /** User agent string. Mirrors Swift `SDKConstants.userAgent`. */
  get userAgent(): string {
    return `${this.name}/${this.version} (React Native)`;
  },

  /**
   * SDK platform identifier used by backend auth/device metadata.
   */
  platform: 'react_native',

  /**
   * Minimum log level in production.
   * Mirrors Swift `SDKConstants.productionLogLevel`.
   */
  productionLogLevel: 'error',
} as const;
