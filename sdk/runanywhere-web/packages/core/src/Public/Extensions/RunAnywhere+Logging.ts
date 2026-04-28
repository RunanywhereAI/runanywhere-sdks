/**
 * RunAnywhere+Logging.ts
 *
 * Logging configuration namespace — mirrors Swift's `RunAnywhere+Logging.swift`.
 * Provides `RunAnywhere.logging.*` surface for controlling SDK log output.
 */

import { SDKLogger, LogLevel } from '../../Foundation/SDKLogger';
export { LogLevel };

export const Logging = {
  setLevel(level: LogLevel): void {
    SDKLogger.level = level;
  },

  getLevel(): LogLevel {
    return SDKLogger.level;
  },

  setEnabled(enabled: boolean): void {
    SDKLogger.enabled = enabled;
  },

  isEnabled(): boolean {
    return SDKLogger.enabled;
  },
};
