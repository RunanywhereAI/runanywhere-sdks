/**
 * RunAnywhere FileSystem Nitrogen Spec
 *
 * Platform-specific file system operations.
 * Implemented in Kotlin (Android) and Swift (iOS).
 */
import type { HybridObject } from 'react-native-nitro-modules';

/**
 * File system operations for model management
 *
 * This is implemented natively in Kotlin/Swift for optimal performance
 * and access to platform-specific APIs (FileManager, java.io).
 */
export interface RunAnywhereFileSystem
  extends HybridObject<{ ios: 'swift'; android: 'kotlin' }> {
  /**
   * Get the RunAnywhere data directory path
   */
  getDataDirectory(): Promise<string>;

  /**
   * Get the models directory path
   */
  getModelsDirectory(): Promise<string>;

  /**
   * Check if a file exists
   * @param path Relative path within data directory
   */
  fileExists(path: string): Promise<boolean>;

  /**
   * Check if a model exists
   * @param modelId Model identifier
   */
  modelExists(modelId: string): Promise<boolean>;

  /**
   * Get the full path to a model
   * @param modelId Model identifier
   */
  getModelPath(modelId: string): Promise<string>;

  /**
   * Download a model from URL
   * @param modelId Model identifier
   * @param url Download URL
   * @param callback Progress callback (0.0 to 1.0)
   */
  downloadModel(
    modelId: string,
    url: string,
    callback?: (progress: number) => void
  ): Promise<void>;

  /**
   * Delete a downloaded model
   * @param modelId Model identifier
   */
  deleteModel(modelId: string): Promise<void>;

  /**
   * Read a text file
   * @param path Relative path within data directory
   */
  readFile(path: string): Promise<string>;

  /**
   * Write a text file
   * @param path Relative path within data directory
   * @param content File content
   */
  writeFile(path: string, content: string): Promise<void>;

  /**
   * Delete a file
   * @param path Relative path within data directory
   */
  deleteFile(path: string): Promise<void>;

  /**
   * Get available disk space in bytes
   */
  getAvailableDiskSpace(): Promise<number>;

  /**
   * Get total disk space in bytes
   */
  getTotalDiskSpace(): Promise<number>;
}

