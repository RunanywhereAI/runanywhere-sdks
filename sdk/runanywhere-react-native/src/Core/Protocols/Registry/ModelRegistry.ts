/**
 * ModelRegistry.ts
 *
 * Model registry protocol
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Protocols/Registry/ModelRegistry.swift
 */

import type { ModelInfo } from '../../Models/Model/ModelInfo';
import { LLMFramework } from '../../Models/Framework/LLMFramework';
import { ModelFormat } from '../../Models/Model/ModelFormat';
import { ModelCategory } from '../../Models/Model/ModelCategory';

/**
 * Model filter criteria
 */
export interface ModelCriteria {
  framework?: LLMFramework;
  format?: ModelFormat;
  category?: ModelCategory;
  available?: boolean;
}

/**
 * Model registry protocol
 */
export interface ModelRegistry {
  /**
   * Discover available models
   * @returns Array of discovered models
   */
  discoverModels(): Promise<ModelInfo[]>;

  /**
   * Register a model
   * @param model - Model to register
   */
  registerModel(model: ModelInfo): void;

  /**
   * Get model by ID
   * @param id - Model identifier
   * @returns Model information if found
   */
  getModel(id: string): ModelInfo | null;

  /**
   * Filter models by criteria
   * @param criteria - Filter criteria
   * @returns Filtered models
   */
  filterModels(criteria: ModelCriteria): ModelInfo[];

  /**
   * Update model information
   * @param model - Updated model information
   */
  updateModel(model: ModelInfo): void;

  /**
   * Remove a model
   * @param id - Model identifier
   */
  removeModel(id: string): void;
}

