/**
 * StoredModel.ts
 * RunAnywhere SDK
 *
 * Represents a model that is stored on disk.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/ModelManagement/Models/Domain/StoredModel.swift
 */

import type { ModelFormat } from '../../../Core/Models/Model/ModelFormat';
import type { InferenceFramework } from './InferenceFramework';

/**
 * Stored model information representing a downloaded/stored model on disk
 */
export interface StoredModel {
  /** Model ID used for operations like deletion */
  id: string;

  /** Human-readable name */
  name: string;

  /** Path to the model on disk */
  path: string;

  /** Size in bytes */
  size: number;

  /** Model file format */
  format: ModelFormat;

  /** Inference framework this model is compatible with */
  framework: InferenceFramework | null;

  /** Date the model was downloaded/created */
  createdDate: Date;

  /** Date the model was last used */
  lastUsed: Date | null;

  /** Tags for categorization */
  tags: string[];

  /** Optional description */
  description: string | null;

  /** Context length for language models */
  contextLength: number | null;

  /** Checksum for integrity verification */
  checksum: string | null;
}

/**
 * Create a StoredModel with required fields and optional defaults
 */
export function createStoredModel(params: {
  id: string;
  name: string;
  path: string;
  size: number;
  format: ModelFormat;
  framework: InferenceFramework | null;
  createdDate: Date;
  lastUsed?: Date | null;
  tags?: string[];
  description?: string | null;
  contextLength?: number | null;
  checksum?: string | null;
}): StoredModel {
  return {
    id: params.id,
    name: params.name,
    path: params.path,
    size: params.size,
    format: params.format,
    framework: params.framework,
    createdDate: params.createdDate,
    lastUsed: params.lastUsed ?? null,
    tags: params.tags ?? [],
    description: params.description ?? null,
    contextLength: params.contextLength ?? null,
    checksum: params.checksum ?? null,
  };
}
