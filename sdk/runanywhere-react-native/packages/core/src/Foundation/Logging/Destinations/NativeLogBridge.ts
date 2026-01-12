/**
 * NativeLogBridge.ts
 *
 * Bridge for receiving native logs (iOS/Android) in TypeScript.
 * Native SDKLoggers forward logs through this bridge to the TypeScript LoggingManager.
 *
 * This enables:
 * - Unified log handling across native and TypeScript
 * - All native logs flowing through TypeScript destinations (Sentry, etc.)
 * - Centralized log configuration
 *
 * Usage:
 *   import { NativeLogBridge } from '@runanywhere/core';
 *
 *   // Initialize bridge (call once at app startup)
 *   NativeLogBridge.initialize();
 *
 *   // Native logs will now flow to TypeScript LoggingManager
 *   // and all registered destinations (Console, Sentry, etc.)
 */

import { LoggingManager, type LogEntry } from '../Services/LoggingManager';
import { LogLevel } from '../Models/LogLevel';

// ============================================================================
// Native Log Entry Interface
// ============================================================================

/**
 * Native log entry structure (from iOS/Android)
 * Matches NativeLogEntry in iOS/Android SDKLogger
 */
export interface NativeLogEntryData {
  level: number;
  category: string;
  message: string;
  metadata?: Record<string, unknown>;
  timestamp: string; // ISO8601 string
}

// ============================================================================
// Native Log Bridge
// ============================================================================

/**
 * Bridge for receiving native logs in TypeScript.
 * Registers as a forwarder on native SDKLoggers.
 */
export class NativeLogBridge {
  private static initialized = false;
  private static nativeLogsEnabled = true;

  /**
   * Initialize the native log bridge.
   * Call this once at app startup to start receiving native logs.
   */
  static initialize(): void {
    if (this.initialized) {
      return;
    }

    // The actual native bridge registration happens automatically
    // when native code calls the forwarder. This is a marker that
    // TypeScript is ready to receive logs.
    this.initialized = true;
  }

  /**
   * Enable or disable native log forwarding to TypeScript
   */
  static setEnabled(enabled: boolean): void {
    this.nativeLogsEnabled = enabled;
  }

  /**
   * Check if native log forwarding is enabled
   */
  static isEnabled(): boolean {
    return this.nativeLogsEnabled;
  }

  /**
   * Handle a log entry from native code.
   * Called by the native bridge when a log is received.
   *
   * @param entryData - Native log entry data
   */
  static handleNativeLog(entryData: NativeLogEntryData): void {
    if (!this.nativeLogsEnabled) {
      return;
    }

    // Convert to TypeScript LogEntry
    const entry: LogEntry = {
      level: entryData.level as LogLevel,
      category: `Native.${entryData.category}`,
      message: entryData.message,
      metadata: entryData.metadata,
      timestamp: new Date(entryData.timestamp),
    };

    // Forward to LoggingManager destinations (except console, since native already logged)
    // We use a special method that skips console but sends to other destinations
    this.forwardToDestinations(entry);
  }

  /**
   * Forward a log entry to non-console destinations.
   * This avoids duplicate console logging (native already logged to console).
   */
  private static forwardToDestinations(entry: LogEntry): void {
    const manager = LoggingManager.shared;
    const destinations = manager.getDestinations();

    for (const destination of destinations) {
      // Skip console destination (native already logged)
      if (destination.identifier === 'console') {
        continue;
      }

      if (destination.isAvailable) {
        try {
          destination.write(entry);
        } catch {
          // Silently ignore destination errors
        }
      }
    }
  }
}

// ============================================================================
// Global handler for native bridge
// ============================================================================

/**
 * Global function that native code can call to forward logs.
 * This is registered as a callback that native code invokes.
 *
 * @param entryJson - JSON string of NativeLogEntryData
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
(global as any).__runanywhereHandleNativeLog = (
  entryData: NativeLogEntryData
): void => {
  NativeLogBridge.handleNativeLog(entryData);
};
