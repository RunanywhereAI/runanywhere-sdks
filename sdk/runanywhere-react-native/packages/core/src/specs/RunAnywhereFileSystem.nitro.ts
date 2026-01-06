import { type HybridObject } from 'react-native-nitro-modules';

/**
 * File system interface for RunAnywhere SDK.
 * Provides file operations and model download functionality.
 */
export interface RunAnywhereFileSystem
  extends HybridObject<{ ios: 'swift'; android: 'kotlin' }> {
  /**
   * Get the data directory path
   */
  getDataDirectory(): Promise<string>;

  /**
   * Get the models directory path
   */
  getModelsDirectory(): Promise<string>;

  /**
   * Check if a file exists at the given path
   */
  fileExists(path: string): Promise<boolean>;

  /**
   * Check if a model exists
   */
  modelExists(modelId: string): Promise<boolean>;

  /**
   * Get the file path for a model
   */
  getModelPath(modelId: string): Promise<string>;

  /**
   * Download a model file with progress callback
   */
  downloadModel(
    modelId: string,
    url: string,
    callback?: (progress: number) => void
  ): Promise<void>;

  /**
   * Delete a model file
   */
  deleteModel(modelId: string): Promise<boolean>;

  /**
   * Read file contents as string
   */
  readFile(path: string): Promise<string>;

  /**
   * Write string contents to a file
   */
  writeFile(path: string, contents: string): Promise<void>;

  /**
   * Delete a file at the given path
   */
  deleteFile(path: string): Promise<boolean>;

  /**
   * Get available disk space in bytes
   */
  getAvailableDiskSpace(): Promise<number>;

  /**
   * Get total disk space in bytes
   */
  getTotalDiskSpace(): Promise<number>;
}
