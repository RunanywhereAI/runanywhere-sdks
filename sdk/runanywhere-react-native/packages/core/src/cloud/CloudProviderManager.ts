/**
 * CloudProviderManager.ts
 *
 * Manages cloud provider registration and selection.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/Cloud/CloudProviderManager.swift
 */

import type { CloudProvider } from './CloudProvider';
import { CloudProviderError } from './OpenAICompatibleProvider';

// ============================================================================
// Cloud Provider Manager
// ============================================================================

/**
 * Central manager for cloud AI providers.
 *
 * Handles provider registration, selection, and lifecycle.
 *
 * @example
 * ```typescript
 * const manager = CloudProviderManager.shared;
 *
 * manager.register(openaiProvider);
 * manager.register(groqProvider);
 *
 * const provider = manager.getDefault();
 * const result = await provider.generate('Hello', { model: 'gpt-4o-mini' });
 * ```
 */
export class CloudProviderManager {
  /** Shared singleton instance */
  static readonly shared = new CloudProviderManager();

  // State
  private providers = new Map<string, CloudProvider>();
  private defaultProviderId?: string;

  // ============================================================================
  // Registration
  // ============================================================================

  /**
   * Register a cloud provider.
   * The first registered provider automatically becomes the default.
   */
  register(provider: CloudProvider): void {
    this.providers.set(provider.providerId, provider);

    // First registered provider becomes the default
    if (this.defaultProviderId === undefined) {
      this.defaultProviderId = provider.providerId;
    }
  }

  /**
   * Unregister a cloud provider by ID.
   */
  unregister(providerId: string): void {
    this.providers.delete(providerId);

    if (this.defaultProviderId === providerId) {
      // Pick the first remaining provider or clear
      const firstKey = this.providers.keys().next().value as string | undefined;
      this.defaultProviderId = firstKey;
    }
  }

  /**
   * Set the default provider by ID.
   * @throws CloudProviderError if provider is not registered
   */
  setDefault(providerId: string): void {
    if (!this.providers.has(providerId)) {
      throw new CloudProviderError(`Cloud provider not found: ${providerId}`);
    }
    this.defaultProviderId = providerId;
  }

  // ============================================================================
  // Provider Access
  // ============================================================================

  /**
   * Get the default cloud provider.
   * @throws CloudProviderError if no provider is registered
   */
  getDefault(): CloudProvider {
    if (this.defaultProviderId === undefined) {
      throw new CloudProviderError('No cloud provider registered');
    }
    const provider = this.providers.get(this.defaultProviderId);
    if (!provider) {
      throw new CloudProviderError('No cloud provider registered');
    }
    return provider;
  }

  /**
   * Get a specific cloud provider by ID.
   * @throws CloudProviderError if provider is not found
   */
  get(providerId: string): CloudProvider {
    const provider = this.providers.get(providerId);
    if (!provider) {
      throw new CloudProviderError(`Cloud provider not found: ${providerId}`);
    }
    return provider;
  }

  /** Get all registered provider IDs */
  get registeredProviderIds(): string[] {
    return Array.from(this.providers.keys());
  }

  /** Check if any providers are registered */
  get hasProviders(): boolean {
    return this.providers.size > 0;
  }

  /** Remove all registered providers */
  removeAll(): void {
    this.providers.clear();
    this.defaultProviderId = undefined;
  }
}
