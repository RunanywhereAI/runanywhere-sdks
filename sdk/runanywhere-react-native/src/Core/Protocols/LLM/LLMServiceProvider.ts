/**
 * LLMServiceProvider.ts
 *
 * Protocol for registering external LLM implementations
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/LLM/LLMComponent.swift
 */

import type { LLMConfiguration } from '../../Models/Configuration/LLMConfiguration';
import type { LLMService } from './LLMService';

/**
 * Protocol for registering external LLM implementations
 */
export interface LLMServiceProvider {
  /**
   * Create an LLM service for the given configuration
   */
  createLLMService(configuration: LLMConfiguration): Promise<LLMService>;

  /**
   * Check if this provider can handle the given model
   */
  canHandle(modelId: string | null | undefined): boolean;

  /**
   * Provider name for identification
   */
  readonly name: string;
}

