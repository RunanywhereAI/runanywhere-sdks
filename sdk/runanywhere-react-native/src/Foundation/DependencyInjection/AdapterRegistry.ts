/**
 * AdapterRegistry.ts
 *
 * Single registry for all framework adapters (text and voice)
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/DependencyInjection/AdapterRegistry.swift
 */

import { LLMFramework } from '../../Core/Models/Framework/LLMFramework';
import { FrameworkModality } from '../../Core/Models/Framework/FrameworkModality';
import type { ModelInfo } from '../../Core/Models/Model/ModelInfo';

/**
 * Unified framework adapter interface
 */
export interface UnifiedFrameworkAdapter {
  readonly framework: LLMFramework;
  readonly supportedModalities: FrameworkModality[];
  readonly supportedFormats: string[];
  canHandle(model: ModelInfo): boolean;
  createService(for modality: FrameworkModality): any | null;
  loadModel(model: ModelInfo, for modality: FrameworkModality): Promise<any>;
  estimateMemoryUsage(for model: ModelInfo): number;
  optimalConfiguration(for model: ModelInfo): any;
  getProvidedModels(): ModelInfo[];
  getDownloadStrategy?(): any;
  onRegistration?(): void;
}

/**
 * Single registry for all framework adapters (text and voice)
 */
export class AdapterRegistry {
  private adapters: Map<LLMFramework, UnifiedFrameworkAdapter> = new Map();

  /**
   * Register a unified framework adapter with optional priority
   */
  public register(adapter: UnifiedFrameworkAdapter, priority: number = 100): void {
    this.adapters.set(adapter.framework, adapter);

    // Call adapter's onRegistration if available
    if (adapter.onRegistration) {
      adapter.onRegistration();
    }

    // Register models provided by the adapter
    const models = adapter.getProvidedModels();
    for (const model of models) {
      // Would register with ServiceContainer.shared.modelRegistry
      // For now, just store
    }

    // Register download strategy if provided
    if (adapter.getDownloadStrategy) {
      const strategy = adapter.getDownloadStrategy();
      // Would register with ServiceContainer.shared.downloadService
    }
  }

  /**
   * Get adapter for a specific framework
   */
  public getAdapter(for framework: LLMFramework): UnifiedFrameworkAdapter | null {
    return this.adapters.get(framework) ?? null;
  }

  /**
   * Find best adapter for a model
   */
  public async findBestAdapter(
    for model: ModelInfo,
    modality?: FrameworkModality
  ): Promise<UnifiedFrameworkAdapter | null> {
    const targetModality = modality ?? this.determineModality(for: model);

    // First try preferred framework
    if (model.preferredFramework) {
      const adapter = this.adapters.get(model.preferredFramework);
      if (adapter && adapter.canHandle(model)) {
        return adapter;
      }
    }

    // Then try compatible frameworks
    for (const framework of model.compatibleFrameworks) {
      const adapter = this.adapters.get(framework);
      if (adapter && adapter.canHandle(model)) {
        return adapter;
      }
    }

    return null;
  }

  /**
   * Get adapters for a specific modality
   */
  public getAdapters(for modality: FrameworkModality): UnifiedFrameworkAdapter[] {
    return Array.from(this.adapters.values()).filter((adapter) =>
      adapter.supportedModalities.includes(modality)
    );
  }

  /**
   * Get all registered adapters
   */
  public getRegisteredAdapters(): Map<LLMFramework, UnifiedFrameworkAdapter> {
    return new Map(this.adapters);
  }

  /**
   * Get available frameworks
   */
  public getAvailableFrameworks(): LLMFramework[] {
    return Array.from(this.adapters.keys());
  }

  /**
   * Determine modality from model info
   */
  private determineModality(for model: ModelInfo): FrameworkModality {
    // Check if it's a speech model
    if (
      model.category === 'speech-recognition' ||
      model.id.toLowerCase().includes('whisper')
    ) {
      return FrameworkModality.VoiceToText;
    }

    // Default to text-to-text for LLMs
    return FrameworkModality.TextToText;
  }
}

