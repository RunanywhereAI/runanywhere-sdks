/**
 * SDKConstants.ts
 *
 * SDK-wide constants (metadata only)
 * Matches iOS: Foundation/Constants/SDKConstants.swift
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Constants/SDKConstants.swift
 */

import { Platform } from 'react-native';

/**
 * SDK-wide constants
 */
export const SDKConstants = {
  /**
   * SDK version - must match the VERSION file in the repository root
   * Update this when bumping the SDK version
   */
  version: '0.15.8',

  /**
   * SDK name
   */
  name: 'RunAnywhere SDK',

  /**
   * User agent string
   */
  get userAgent(): string {
    return `${SDKConstants.name}/${SDKConstants.version} (React Native)`;
  },

  /**
   * Platform identifier
   */
  get platform(): string {
    return Platform.OS;
  },

  /**
   * Minimum log level in production
   */
  productionLogLevel: 'error',
} as const;

export default SDKConstants;
