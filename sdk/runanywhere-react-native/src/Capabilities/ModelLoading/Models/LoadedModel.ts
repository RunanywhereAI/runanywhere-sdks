/**
 * LoadedModel.ts
 *
 * Represents a model that has been loaded and is ready for use
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/ModelLoading/Models/LoadedModel.swift
 */

import type { ModelInfo } from '../../../Core/Models/Model/ModelInfo';
import type { LLMService } from '../../../Core/Protocols/LLM/LLMService';

/**
 * Represents a model that has been loaded and is ready for use
 */
export interface LoadedModel {
  /** The model information */
  readonly model: ModelInfo;

  /** The service that can execute this model */
  readonly service: LLMService;
}

/**
 * Create loaded model
 */
export class LoadedModelImpl implements LoadedModel {
  public readonly model: ModelInfo;
  public readonly service: LLMService;

  constructor(model: ModelInfo, service: LLMService) {
    this.model = model;
    this.service = service;
  }
}
