/**
 * STTServiceProvider.ts
 *
 * Protocol for registering external STT implementations
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/STT/STTComponent.swift
 */

import type { STTConfiguration } from '../../../Features/STT/STTConfiguration';
import type { STTService } from './STTService';

/**
 * Protocol for registering external STT implementations
 *
 * Providers implement this protocol to register their STT service
 * with the ServiceRegistry, enabling plugin-based architecture.
 */
export interface STTServiceProvider {
  /**
   * Create an STT service for the given configuration
   *
   * @param configuration - STT configuration
   * @returns Promise resolving to STT service instance
   * @throws Error if service creation fails
   */
  createSTTService(configuration: STTConfiguration): Promise<STTService>;

  /**
   * Check if this provider can handle the given model
   *
   * @param modelId - Optional model ID to check
   * @returns true if this provider can handle the model
   */
  canHandle(modelId: string | null | undefined): boolean;

  /**
   * Provider name for identification
   */
  readonly name: string;
}
