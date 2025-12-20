/**
 * LLMServiceProvider.ts
 *
 * Protocol for registering external LLM implementations
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/LLM/LLMComponent.swift
 */

import type { LLMConfiguration } from '../../../Features/LLM/LLMConfiguration';
import type { LLMService } from './LLMService';
import type { ModelInfo } from '../../../types';

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

  /**
   * Get models provided by this provider (optional)
   *
   * Called during provider registration to populate ModelRegistry.
   * Providers can expose their supported models.
   */
  getProvidedModels?(): ModelInfo[];

  /**
   * Lifecycle hook called when provider is registered (optional)
   *
   * Called by ServiceRegistry after provider registration.
   * Use this to register models, configure dependencies, etc.
   */
  onRegistration?(): void;
}
