/**
 * MemoryManager.ts
 *
 * Protocol for memory management
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Protocols/Memory/MemoryManager.swift
 */

// Placeholder types - will be defined in their respective files
export interface LoadedModel {
  id: string;
  name: string;
  [key: string]: any;
}

export interface LLMService {
  [key: string]: any;
}

/**
 * Memory priority levels
 */
export enum MemoryPriority {
  Low = 0,
  Normal = 1,
  High = 2,
  Critical = 3,
}

/**
 * Memory-tracked model information
 */
export interface MemoryLoadedModel {
  readonly id: string;
  readonly name: string;
  readonly size: number; // bytes
  readonly framework: string;
  readonly loadedAt: Date;
  lastUsed: Date;
  readonly priority: MemoryPriority;
}

/**
 * Lifecycle stages for progress tracking
 */
export enum LifecycleStage {
  Discovery = 'Discovery',
  Download = 'Download',
  Extraction = 'Extraction',
  Validation = 'Validation',
  Initialization = 'Initialization',
  Loading = 'Loading',
  Ready = 'Ready',
}

/**
 * Get default message for a lifecycle stage
 */
export function getLifecycleStageMessage(stage: LifecycleStage): string {
  switch (stage) {
    case LifecycleStage.Discovery:
      return 'Discovering model...';
    case LifecycleStage.Download:
      return 'Downloading model...';
    case LifecycleStage.Extraction:
      return 'Extracting files...';
    case LifecycleStage.Validation:
      return 'Validating model...';
    case LifecycleStage.Initialization:
      return 'Initializing model...';
    case LifecycleStage.Loading:
      return 'Loading model...';
    case LifecycleStage.Ready:
      return 'Model ready';
  }
}

/**
 * Overall progress information
 */
export interface OverallProgress {
  readonly percentage: number; // 0.0 to 1.0
  readonly currentStage: LifecycleStage | null;
  readonly stageProgress: number; // 0.0 to 1.0
  readonly message: string;
  readonly estimatedTimeRemaining: number | null; // milliseconds
}

/**
 * Progress observer protocol
 */
export interface ProgressObserver {
  /**
   * Called when progress is updated
   * @param progress - The current progress
   */
  progressDidUpdate(progress: OverallProgress): void;

  /**
   * Called when a stage completes
   * @param stage - The completed stage
   */
  stageDidComplete(stage: LifecycleStage): void;

  /**
   * Called when a stage fails
   * @param stage - The failed stage
   * @param error - The error that occurred
   */
  stageDidFail(stage: LifecycleStage, error: Error): void;
}

/**
 * Protocol for memory management
 */
export interface MemoryManager {
  /**
   * Register a loaded model
   * @param model - The loaded model
   * @param size - Memory size in bytes
   * @param service - The LLM service managing the model
   */
  registerLoadedModel(model: LoadedModel, size: number, service: LLMService): void;

  /**
   * Unregister a model
   * @param modelId - The model identifier
   */
  unregisterModel(modelId: string): void;

  /**
   * Get current memory usage
   * @returns Current memory usage in bytes
   */
  getCurrentMemoryUsage(): number;

  /**
   * Get available memory
   * @returns Available memory in bytes
   */
  getAvailableMemory(): number;

  /**
   * Check if enough memory is available
   * @param size - Required memory size
   * @returns Whether enough memory is available
   */
  hasAvailableMemory(forSize: number): boolean;

  /**
   * Check if memory can be allocated for a specific size
   * @param size - Required memory size
   * @returns Whether memory can be allocated
   */
  canAllocate(size: number): Promise<boolean>;

  /**
   * Handle memory pressure
   */
  handleMemoryPressure(): Promise<void>;

  /**
   * Set memory threshold
   * @param threshold - Memory threshold in bytes
   */
  setMemoryThreshold(threshold: number): void;

  /**
   * Get loaded models
   * @returns Array of loaded model information
   */
  getLoadedModels(): MemoryLoadedModel[];

  /**
   * Request memory for a model
   * @param size - Required memory size
   * @param priority - Priority of the request
   * @returns Whether memory was allocated
   */
  requestMemory(size: number, priority: MemoryPriority): Promise<boolean>;

  /**
   * Check if the memory manager is healthy and operational
   * @returns Whether the service is healthy
   */
  isHealthy(): boolean;
}

