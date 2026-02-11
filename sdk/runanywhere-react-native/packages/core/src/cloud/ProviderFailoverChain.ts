/**
 * ProviderFailoverChain.ts
 *
 * Provider failover chain with priority ordering and circuit breaker.
 * Mirrors Swift ProviderFailoverChain.swift exactly.
 */

import type { CloudProvider } from './CloudProvider';
import type { CloudGenerationOptions, CloudGenerationResult } from './CloudTypes';

// ============================================================================
// Provider Health Status
// ============================================================================

export interface ProviderHealthStatus {
  providerId: string;
  displayName: string;
  priority: number;
  consecutiveFailures: number;
  isCircuitOpen: boolean;
  lastFailureTime: number | null;
}

// ============================================================================
// Internal Types
// ============================================================================

interface ProviderEntry {
  provider: CloudProvider;
  priority: number;
  consecutiveFailures: number;
  lastFailureTime: number | null;
  isCircuitOpen: boolean;
}

// ============================================================================
// Provider Failover Chain
// ============================================================================

/**
 * Manages a priority-ordered chain of cloud providers with automatic failover.
 *
 * If the primary provider fails, the chain tries the next provider.
 * Includes a simple circuit breaker to avoid repeatedly calling unhealthy providers.
 *
 * ```typescript
 * const chain = new ProviderFailoverChain();
 * chain.addProvider(openaiProvider, 100);
 * chain.addProvider(groqProvider, 50);  // lower priority = fallback
 * ```
 */
export class ProviderFailoverChain {
  private readonly circuitBreakerThreshold: number;
  private readonly circuitBreakerCooldownMs: number;
  private entries: ProviderEntry[] = [];

  constructor(
    circuitBreakerThreshold = 3,
    circuitBreakerCooldownSeconds = 60,
  ) {
    this.circuitBreakerThreshold = circuitBreakerThreshold;
    this.circuitBreakerCooldownMs = circuitBreakerCooldownSeconds * 1000;
  }

  // ============================================================================
  // Configuration
  // ============================================================================

  /** Add a provider with a priority (higher = preferred) */
  addProvider(provider: CloudProvider, priority: number): void {
    this.entries.push({
      provider,
      priority,
      consecutiveFailures: 0,
      lastFailureTime: null,
      isCircuitOpen: false,
    });
    this.entries.sort((a, b) => b.priority - a.priority);
  }

  /** Remove a provider by ID */
  removeProvider(providerId: string): void {
    this.entries = this.entries.filter(
      (e) => e.provider.providerId !== providerId,
    );
  }

  // ============================================================================
  // Execution
  // ============================================================================

  /** Try generation across the provider chain with failover */
  async generate(
    prompt: string,
    options: CloudGenerationOptions,
  ): Promise<CloudGenerationResult> {
    let lastError: Error | null = null;

    for (let i = 0; i < this.entries.length; i++) {
      const entry = this.entries[i]!;

      // Skip providers with open circuits (unless cooldown elapsed)
      if (entry.isCircuitOpen) {
        if (entry.lastFailureTime != null) {
          const elapsed = Date.now() - entry.lastFailureTime;
          if (elapsed < this.circuitBreakerCooldownMs) {
            continue;
          }
        }
        // Cooldown elapsed, try half-open
        entry.isCircuitOpen = false;
      }

      try {
        const result = await entry.provider.generate(prompt, options);

        // Success: reset failure count
        entry.consecutiveFailures = 0;
        entry.isCircuitOpen = false;

        return result;
      } catch (error) {
        lastError =
          error instanceof Error ? error : new Error(String(error));

        // Record failure
        entry.consecutiveFailures += 1;
        entry.lastFailureTime = Date.now();

        // Open circuit if threshold reached
        if (entry.consecutiveFailures >= this.circuitBreakerThreshold) {
          entry.isCircuitOpen = true;
        }
      }
    }

    throw lastError ?? new Error('No cloud provider registered');
  }

  /** Try streaming generation across the provider chain */
  async *generateStream(
    prompt: string,
    options: CloudGenerationOptions,
  ): AsyncGenerator<string> {
    for (const entry of this.entries) {
      if (entry.isCircuitOpen) {
        if (entry.lastFailureTime != null) {
          const elapsed = Date.now() - entry.lastFailureTime;
          if (elapsed < this.circuitBreakerCooldownMs) {
            continue;
          }
        }
        entry.isCircuitOpen = false;
      }

      // For streaming, return the first available provider's stream
      // Failover during streaming is more complex and deferred to future
      if (await entry.provider.isAvailable()) {
        entry.consecutiveFailures = 0;
        yield* entry.provider.generateStream(prompt, options);
        return;
      }
    }

    throw new Error('No cloud provider registered');
  }

  // ============================================================================
  // Health Status
  // ============================================================================

  /** Get health status of all providers */
  get healthStatus(): ProviderHealthStatus[] {
    return this.entries.map((entry) => ({
      providerId: entry.provider.providerId,
      displayName: entry.provider.displayName,
      priority: entry.priority,
      consecutiveFailures: entry.consecutiveFailures,
      isCircuitOpen: entry.isCircuitOpen,
      lastFailureTime: entry.lastFailureTime,
    }));
  }
}
