/**
 * ModelLifecycleManager.ts
 *
 * Unified model lifecycle management for all capabilities.
 * Handles loading, unloading, and downloading of models/resources.
 *
 * Matches iOS: Core/Capabilities/ModelLifecycleManager.swift
 */

import type {
  CapabilityLoadingState,
  ComponentConfiguration,
} from './CapabilityProtocols';
import {
  idleState,
  loadingState,
  loadedState,
  CapabilityError,
} from './CapabilityProtocols';

// ============================================================================
// Types
// ============================================================================

/**
 * Load resource function signature.
 * Takes resource ID and optional configuration, returns the loaded service.
 */
export type LoadResourceFn<TService> = (
  resourceId: string,
  config: ComponentConfiguration | null
) => Promise<TService>;

/**
 * Unload resource function signature.
 * Takes the service and performs cleanup.
 */
export type UnloadResourceFn<TService> = (service: TService) => Promise<void>;

/**
 * Options for creating a ModelLifecycleManager
 */
export interface ModelLifecycleManagerOptions<TService> {
  /**
   * Logger category for debug output
   */
  category: string;

  /**
   * Function to load a resource
   */
  loadResource: LoadResourceFn<TService>;

  /**
   * Function to unload a resource
   */
  unloadResource: UnloadResourceFn<TService>;
}

// ============================================================================
// Model Lifecycle Manager
// ============================================================================

/**
 * Unified manager for model/resource lifecycle across all capabilities.
 * Handles loading, unloading, state tracking, and concurrent access.
 *
 * Key features:
 * - Prevents duplicate loads (if already loaded with same ID, returns existing)
 * - Coalesces concurrent load requests (waits for in-flight load)
 * - Auto-unloads old resource before loading new one
 *
 * @example
 * ```typescript
 * const manager = new ModelLifecycleManager({
 *   category: 'LLM.Lifecycle',
 *   loadResource: async (id, config) => {
 *     return await createLLMService(id, config);
 *   },
 *   unloadResource: async (service) => {
 *     await service.cleanup();
 *   }
 * });
 *
 * const service = await manager.load('llama-7b');
 * ```
 */
export class ModelLifecycleManager<TService> {
  // MARK: - State

  private service: TService | null = null;
  private loadedResourceId: string | null = null;
  private inflightPromise: Promise<TService> | null = null;
  private configuration: ComponentConfiguration | null = null;

  // MARK: - Dependencies

  private readonly category: string;
  private readonly loadResourceFn: LoadResourceFn<TService>;
  private readonly unloadResourceFn: UnloadResourceFn<TService>;

  // MARK: - Initialization

  constructor(options: ModelLifecycleManagerOptions<TService>) {
    this.category = options.category;
    this.loadResourceFn = options.loadResource;
    this.unloadResourceFn = options.unloadResource;
  }

  // MARK: - State Properties

  /**
   * Whether a resource is currently loaded
   */
  get isLoaded(): boolean {
    return this.service !== null;
  }

  /**
   * The currently loaded resource ID
   */
  get currentResourceId(): string | null {
    return this.loadedResourceId;
  }

  /**
   * The currently loaded service
   */
  get currentService(): TService | null {
    return this.service;
  }

  /**
   * Current loading state
   */
  get state(): CapabilityLoadingState {
    if (this.loadedResourceId !== null) {
      return loadedState(this.loadedResourceId);
    }
    if (this.inflightPromise !== null) {
      return loadingState('');
    }
    return idleState();
  }

  // MARK: - Configuration

  /**
   * Set configuration for loading
   */
  configure(config: ComponentConfiguration | null): void {
    this.configuration = config;
  }

  // MARK: - Lifecycle Operations

  /**
   * Load a resource by ID.
   *
   * @param resourceId - The resource identifier
   * @returns The loaded service
   * @throws CapabilityError if loading fails
   */
  async load(resourceId: string): Promise<TService> {
    // Check if already loaded with same ID
    if (this.loadedResourceId === resourceId && this.service !== null) {
      this.log(`Resource already loaded: ${resourceId}`);
      return this.service;
    }

    // Wait for existing load to complete
    if (this.inflightPromise !== null) {
      this.log('Load in progress, waiting...');
      try {
        const result = await this.inflightPromise;
        // Check if the completed load was for our resource
        if (this.loadedResourceId === resourceId) {
          return result;
        }
      } catch {
        // Previous load failed, continue with new load
      }
    }

    // Unload current if different
    if (this.service !== null && this.loadedResourceId !== resourceId) {
      this.log('Unloading current resource before loading new one');
      await this.unloadResourceFn(this.service);
      this.service = null;
      this.loadedResourceId = null;
    }

    // Create loading promise
    const config = this.configuration;
    const loadPromise = this.loadResourceFn(resourceId, config);

    this.inflightPromise = loadPromise;

    try {
      const loadedService = await loadPromise;
      this.service = loadedService;
      this.loadedResourceId = resourceId;
      this.inflightPromise = null;
      this.log(`Resource loaded successfully: ${resourceId}`);
      return loadedService;
    } catch (error) {
      this.inflightPromise = null;
      this.logError(`Failed to load resource: ${error}`);
      throw CapabilityError.loadFailed(
        resourceId,
        error instanceof Error ? error : undefined
      );
    }
  }

  /**
   * Unload the currently loaded resource
   */
  async unload(): Promise<void> {
    if (this.service === null) {
      return;
    }

    this.log(`Unloading resource: ${this.loadedResourceId ?? 'unknown'}`);
    await this.unloadResourceFn(this.service);
    this.service = null;
    this.loadedResourceId = null;
    this.log('Resource unloaded successfully');
  }

  /**
   * Reset all state
   */
  async reset(): Promise<void> {
    // Note: We can't truly cancel a promise in JS, but we can ignore its result
    this.inflightPromise = null;

    if (this.service !== null) {
      await this.unloadResourceFn(this.service);
    }

    this.service = null;
    this.loadedResourceId = null;
    this.configuration = null;
  }

  /**
   * Get service or throw if not loaded
   */
  requireService(): TService {
    if (this.service === null) {
      throw CapabilityError.resourceNotLoaded('resource');
    }
    return this.service;
  }

  // MARK: - Private Helpers

  private log(message: string): void {
    console.log(`[${this.category}] ${message}`);
  }

  private logError(message: string): void {
    console.error(`[${this.category}] ${message}`);
  }
}
