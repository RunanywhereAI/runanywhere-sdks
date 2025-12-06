/**
 * ModelInfoMetadata.ts
 *
 * Model information metadata
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Models/Model/ModelInfoMetadata.swift
 */

import { QuantizationLevel } from '../Common/QuantizationLevel';

/**
 * Model information metadata
 */
export interface ModelInfoMetadata {
  readonly author: string | null;
  readonly license: string | null;
  readonly tags: string[];
  readonly description: string | null;
  readonly trainingDataset: string | null;
  readonly baseModel: string | null;
  readonly quantizationLevel: QuantizationLevel | null;
  readonly version: string | null;
  readonly minOSVersion: string | null;
  readonly minMemory: number | null; // Int64
}

/**
 * Create model info metadata
 */
export class ModelInfoMetadataImpl implements ModelInfoMetadata {
  public readonly author: string | null;
  public readonly license: string | null;
  public readonly tags: string[];
  public readonly description: string | null;
  public readonly trainingDataset: string | null;
  public readonly baseModel: string | null;
  public readonly quantizationLevel: QuantizationLevel | null;
  public readonly version: string | null;
  public readonly minOSVersion: string | null;
  public readonly minMemory: number | null;

  constructor(options: {
    author?: string | null;
    license?: string | null;
    tags?: string[];
    description?: string | null;
    trainingDataset?: string | null;
    baseModel?: string | null;
    quantizationLevel?: QuantizationLevel | null;
    version?: string | null;
    minOSVersion?: string | null;
    minMemory?: number | null;
  } = {}) {
    this.author = options.author ?? null;
    this.license = options.license ?? null;
    this.tags = options.tags ?? [];
    this.description = options.description ?? null;
    this.trainingDataset = options.trainingDataset ?? null;
    this.baseModel = options.baseModel ?? null;
    this.quantizationLevel = options.quantizationLevel ?? null;
    this.version = options.version ?? null;
    this.minOSVersion = options.minOSVersion ?? null;
    this.minMemory = options.minMemory ?? null;
  }
}

