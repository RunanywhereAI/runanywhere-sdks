/**
 * SDK-wide constants.
 *
 * Mirrors `sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Constants/SDKConstants.swift`.
 */

export const SDKConstants = {
  /**
   * SDK version - must stay in sync with package.json `version`.
   * Native commons receives this through the Phase 1 init payload.
   */
  version: '0.19.13',

  /**
   * SDK platform identifier used by backend auth/device metadata.
   */
  platform: 'react_native',
} as const;
