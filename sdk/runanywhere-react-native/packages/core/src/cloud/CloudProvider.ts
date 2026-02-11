/**
 * CloudProvider.ts
 *
 * Protocol for cloud AI providers (OpenAI-compatible APIs).
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Cloud/CloudProvider.swift
 */

import type { CloudGenerationOptions, CloudGenerationResult } from './CloudTypes';

// ============================================================================
// Cloud Provider Interface
// ============================================================================

/**
 * Interface for cloud AI inference providers.
 *
 * Implement this interface to add a custom cloud provider for hybrid routing.
 * The SDK ships with `OpenAICompatibleProvider` which works with any
 * OpenAI-compatible API (OpenAI, Groq, Together, Ollama, etc.).
 *
 * @example
 * ```typescript
 * const provider = new OpenAICompatibleProvider({
 *   apiKey: 'sk-...',
 *   model: 'gpt-4o-mini',
 * });
 * RunAnywhere.registerCloudProvider(provider);
 * ```
 */
export interface CloudProvider {
  /** Unique identifier for this provider */
  readonly providerId: string;

  /** Human-readable display name */
  readonly displayName: string;

  /** Generate text (non-streaming) */
  generate(prompt: string, options: CloudGenerationOptions): Promise<CloudGenerationResult>;

  /** Generate text with streaming */
  generateStream(prompt: string, options: CloudGenerationOptions): AsyncGenerator<string>;

  /** Check if the provider is available and configured */
  isAvailable(): Promise<boolean>;
}
