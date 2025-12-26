/**
 * NetworkRetry.ts
 *
 * Reusable async retry utility for network operations
 *
 * Matches iOS SDK: Foundation/Utilities/NetworkRetry.swift
 */

import { SDKLogger } from '../Logging/Logger/SDKLogger';
import { SDKError } from '../ErrorTypes/SDKError';
import { ErrorCode } from '../ErrorTypes/ErrorCodes';

/**
 * Configuration for retry behavior
 */
export interface RetryConfig {
  /** Maximum number of attempts (including initial attempt) */
  readonly maxAttempts: number;
  /** Delay between retries in seconds */
  readonly delaySeconds: number;
  /** Whether to use exponential backoff */
  readonly exponentialBackoff: boolean;
}

/**
 * Default retry configurations
 */
export const RetryConfigs = {
  /** Default configuration: 3 attempts, 2s delay, no exponential backoff */
  default: {
    maxAttempts: 3,
    delaySeconds: 2.0,
    exponentialBackoff: false,
  } as RetryConfig,

  /** Aggressive configuration: 5 attempts, 1s delay, exponential backoff */
  aggressive: {
    maxAttempts: 5,
    delaySeconds: 1.0,
    exponentialBackoff: true,
  } as RetryConfig,
};

/**
 * Reusable retry utility for async operations
 */
export class NetworkRetry {
  private static readonly logger = new SDKLogger('NetworkRetry');

  /**
   * Execute an async operation with retry logic
   *
   * @param config - Retry configuration
   * @param operation - The async operation to execute
   * @returns The result of the operation
   * @throws The last error if all retries fail
   */
  static async execute<T>(
    config: RetryConfig = RetryConfigs.default,
    operation: () => Promise<T>
  ): Promise<T> {
    let lastError: Error | undefined;

    for (let attempt = 1; attempt <= config.maxAttempts; attempt++) {
      try {
        return await operation();
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));

        // Don't retry non-retryable errors
        if (!this.isRetryable(lastError)) {
          throw lastError;
        }

        // Don't wait after the last attempt
        if (attempt >= config.maxAttempts) {
          break;
        }

        const delay = config.exponentialBackoff
          ? config.delaySeconds * Math.pow(2.0, attempt - 1)
          : config.delaySeconds;

        this.logger.debug(
          `Attempt ${attempt} failed, retrying in ${delay}s: ${lastError.message}`
        );

        await this.sleep(delay);
      }
    }

    throw (
      lastError ??
      new SDKError(
        ErrorCode.NetworkUnavailable,
        `Operation failed after ${config.maxAttempts} attempts`
      )
    );
  }

  /**
   * Execute an async operation with retry, returning null on failure instead of throwing
   *
   * @param config - Retry configuration
   * @param operation - The async operation to execute
   * @returns The result of the operation or null if all attempts fail
   */
  static async executeOptional<T>(
    config: RetryConfig = RetryConfigs.default,
    operation: () => Promise<T>
  ): Promise<T | null> {
    try {
      return await this.execute(config, operation);
    } catch {
      return null;
    }
  }

  /**
   * Check if an error is retryable
   */
  private static isRetryable(error: Error): boolean {
    // SDK errors
    if (error instanceof SDKError) {
      switch (error.code) {
        case ErrorCode.NetworkUnavailable:
        case ErrorCode.NetworkTimeout:
        case ErrorCode.ApiError:
          return true;
        default:
          return false;
      }
    }

    // Network errors by message patterns (for non-SDK errors)
    const message = error.message.toLowerCase();
    const retryablePatterns = [
      'network',
      'timeout',
      'timed out',
      'connection',
      'econnrefused',
      'enotfound',
      'etimedout',
      'econnreset',
      'fetch failed',
      'failed to fetch',
    ];

    return retryablePatterns.some((pattern) => message.includes(pattern));
  }

  /**
   * Sleep for a specified duration in seconds
   */
  private static sleep(seconds: number): Promise<void> {
    return new Promise((resolve) => {
      setTimeout(resolve, seconds * 1000);
    });
  }
}
