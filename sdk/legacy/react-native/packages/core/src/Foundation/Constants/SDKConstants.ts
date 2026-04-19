/**
 * SDK-wide constants (metadata only)
 *
 * Centralized constants to ensure consistency across the SDK.
 * Matches pattern: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Constants/SDKConstants.swift
 */

import { Platform } from 'react-native';

/**
 * SDK Constants
 *
 * All SDK-wide constants should be defined here to avoid hardcoded values
 * scattered throughout the codebase.
 */
export const SDKConstants = {
  /**
   * SDK version - must match the VERSION file in the repository root
   * Update this when bumping the SDK version
   */
  version: '0.2.0',

  /**
   * SDK name
   */
  name: 'RunAnywhere SDK',

  /**
   * User agent string
   */
  get userAgent(): string {
    return `${this.name}/${this.version} (React Native)`;
  },

  /**
   * Platform identifier (ios/android)
   */
  get platform(): string {
    return Platform.OS === 'ios' ? 'ios' : 'android';
  },

  /**
   * Minimum log level in production
   */
  productionLogLevel: 'error',
} as const;

