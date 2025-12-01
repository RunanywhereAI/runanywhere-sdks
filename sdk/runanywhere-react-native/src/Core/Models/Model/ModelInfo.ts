/**
 * ModelInfo.ts
 *
 * Information about a model
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Models/Model/ModelInfo.swift
 */

import { ModelCategory } from './ModelCategory';
import { ModelFormat } from './ModelFormat';
import { LLMFramework } from '../Framework/LLMFramework';
import { ThinkingTagPattern } from '../../Capabilities/TextGeneration/Models/ThinkingTagPattern';
import { ModelInfoMetadata } from './ModelInfoMetadata';
import { ConfigurationSource } from '../Configuration/ConfigurationSource';
import { requiresContextLength, supportsThinking as categorySupportsThinking } from './ModelCategory';

/**
 * Information about a model
 */
export interface ModelInfo {
  /** Essential identifiers */
  readonly id: string;
  readonly name: string;
  readonly category: ModelCategory; // Type of model (language, speech, vision, etc.)

  /** Format and location */
  readonly format: ModelFormat;
  readonly downloadURL: string | null;
  localPath: string | null;

  /** Size information (in bytes) */
  readonly downloadSize: number | null; // Int64 - Size when downloading
  readonly memoryRequired: number | null; // Int64 - RAM needed to run the model

  /** Framework compatibility */
  readonly compatibleFrameworks: LLMFramework[];
  readonly preferredFramework: LLMFramework | null;

  /** Model-specific capabilities (optional based on category) */
  readonly contextLength: number | null; // For language models
  readonly supportsThinking: boolean; // For reasoning models
  readonly thinkingPattern: ThinkingTagPattern | null; // Custom thinking pattern (if supportsThinking)

  /** Optional metadata */
  readonly metadata: ModelInfoMetadata | null;

  /** Tracking fields for sync and database */
  readonly source: ConfigurationSource;
  readonly createdAt: Date;
  updatedAt: Date;
  syncPending: boolean;

  /** Usage tracking */
  lastUsed: Date | null;
  usageCount: number;

  /** Non-Codable runtime properties */
  additionalProperties: { [key: string]: string };
}

/**
 * Create model info
 */
export class ModelInfoImpl implements ModelInfo {
  public readonly id: string;
  public readonly name: string;
  public readonly category: ModelCategory;
  public readonly format: ModelFormat;
  public readonly downloadURL: string | null;
  public localPath: string | null;
  public readonly downloadSize: number | null;
  public readonly memoryRequired: number | null;
  public readonly compatibleFrameworks: LLMFramework[];
  public readonly preferredFramework: LLMFramework | null;
  public readonly contextLength: number | null;
  public readonly supportsThinking: boolean;
  public readonly thinkingPattern: ThinkingTagPattern | null;
  public readonly metadata: ModelInfoMetadata | null;
  public readonly source: ConfigurationSource;
  public readonly createdAt: Date;
  public updatedAt: Date;
  public syncPending: boolean;
  public lastUsed: Date | null;
  public usageCount: number;
  public additionalProperties: { [key: string]: string };

  constructor(options: {
    id: string;
    name: string;
    category: ModelCategory;
    format: ModelFormat;
    downloadURL?: string | null;
    localPath?: string | null;
    downloadSize?: number | null;
    memoryRequired?: number | null;
    compatibleFrameworks?: LLMFramework[];
    preferredFramework?: LLMFramework | null;
    contextLength?: number | null;
    supportsThinking?: boolean;
    thinkingPattern?: ThinkingTagPattern | null;
    metadata?: ModelInfoMetadata | null;
    source?: ConfigurationSource;
    createdAt?: Date;
    updatedAt?: Date;
    syncPending?: boolean;
    lastUsed?: Date | null;
    usageCount?: number;
    additionalProperties?: { [key: string]: string };
  }) {
    this.id = options.id;
    this.name = options.name;
    this.category = options.category;
    this.format = options.format;
    this.downloadURL = options.downloadURL ?? null;
    this.localPath = options.localPath ?? null;
    this.downloadSize = options.downloadSize ?? null;
    this.memoryRequired = options.memoryRequired ?? null;
    this.compatibleFrameworks = options.compatibleFrameworks ?? [];
    this.preferredFramework = options.preferredFramework ?? options.compatibleFrameworks?.[0] ?? null;
    this.metadata = options.metadata ?? null;
    this.source = options.source ?? ConfigurationSource.Remote;
    this.createdAt = options.createdAt ?? new Date();
    this.updatedAt = options.updatedAt ?? new Date();
    this.syncPending = options.syncPending ?? false;
    this.lastUsed = options.lastUsed ?? null;
    this.usageCount = options.usageCount ?? 0;
    this.additionalProperties = options.additionalProperties ?? {};

    // Set contextLength based on category if not provided
    if (requiresContextLength(this.category)) {
      this.contextLength = options.contextLength ?? 2048;
    } else {
      this.contextLength = options.contextLength ?? null;
    }

    // Set supportsThinking based on category
    if (categorySupportsThinking(this.category)) {
      this.supportsThinking = options.supportsThinking ?? false;
    } else {
      this.supportsThinking = false;
    }

    // Set thinking pattern based on supportsThinking
    if (this.supportsThinking) {
      const { ThinkingTagPattern } = require('../../Capabilities/TextGeneration/Models/ThinkingTagPattern');
      this.thinkingPattern = options.thinkingPattern ?? ThinkingTagPattern.defaultPattern;
    } else {
      this.thinkingPattern = null;
    }
  }

  /**
   * Whether this model is downloaded and available locally
   */
  public get isDownloaded(): boolean {
    if (!this.localPath) {
      return false;
    }

    // Built-in models (e.g., Apple Foundation Models) are always available
    if (this.localPath.startsWith('builtin://')) {
      return true;
    }

    // In React Native, we can't directly check file existence
    // This would need to be implemented via native modules
    // For now, assume if localPath is set, it's downloaded
    return this.localPath !== null;
  }

  /**
   * Whether this model is available for use (downloaded and locally accessible)
   */
  public get isAvailable(): boolean {
    return this.isDownloaded;
  }
}

