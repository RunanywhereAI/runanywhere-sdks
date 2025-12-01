/**
 * InferenceRequest.ts
 *
 * Request for inference
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/TextGeneration/Models/InferenceRequest.swift
 */

import { RequestPriority } from '../../Core/Models/Common/RequestPriority';
import type { GenerationOptions } from './GenerationOptions';

/**
 * Request for inference
 */
export interface InferenceRequest {
  readonly id: string; // UUID
  readonly prompt: string;
  readonly options: GenerationOptions | null;
  readonly timestamp: Date;
  readonly estimatedTokens: number | null;
  readonly priority: RequestPriority;
}

/**
 * Create an inference request
 */
export class InferenceRequestImpl implements InferenceRequest {
  public readonly id: string;
  public readonly prompt: string;
  public readonly options: GenerationOptions | null;
  public readonly timestamp: Date;
  public readonly estimatedTokens: number | null;
  public readonly priority: RequestPriority;

  constructor(
    prompt: string,
    options: GenerationOptions | null = null,
    estimatedTokens: number | null = null,
    priority: RequestPriority = RequestPriority.Normal
  ) {
    this.id = crypto.randomUUID();
    this.prompt = prompt;
    this.options = options;
    this.timestamp = new Date();
    this.estimatedTokens = estimatedTokens;
    this.priority = priority;
  }
}

