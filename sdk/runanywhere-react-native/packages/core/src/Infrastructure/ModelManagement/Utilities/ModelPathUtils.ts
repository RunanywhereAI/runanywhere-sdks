/**
 * ModelPathUtils.ts
 *
 * Centralized utility for calculating model paths and directories.
 * Located in ModelManagement as it deals with model-specific path logic.
 *
 * Follows the structure: `Documents/RunAnywhere/Models/{framework}/{modelId}/`
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/ModelManagement/Utilities/ModelPathUtils.swift
 */

import RNFS from 'react-native-fs';
import { ModelFormat } from '../../../Core/Models/Model/ModelFormat';
import { InferenceFramework } from '../Models/InferenceFramework';
import {
  SDKError,
  SDKErrorCode,
} from '../../../Foundation/ErrorTypes/SDKError';

/**
 * Centralized utility for calculating model paths and directories.
 * Follows the structure: `Documents/RunAnywhere/Models/{framework}/{modelId}/`
 *
 * This utility ensures consistent path calculation across the entire SDK,
 * preventing scattered path logic and reducing potential bugs.
 */
export class ModelPathUtils {
  // MARK: - Base Directories

  /**
   * Get the base RunAnywhere directory in Documents
   * @returns Path to `Documents/RunAnywhere/`
   * @throws If Documents directory is not accessible
   */
  static getBaseDirectory(): string {
    const documentsPath = RNFS.DocumentDirectoryPath;
    if (!documentsPath) {
      throw new SDKError(
        SDKErrorCode.StorageError,
        'Documents directory not accessible'
      );
    }
    return `${documentsPath}/RunAnywhere`;
  }

  /**
   * Get the models directory
   * @returns Path to `Documents/RunAnywhere/Models/`
   * @throws If base directory cannot be accessed
   */
  static getModelsDirectory(): string {
    return `${this.getBaseDirectory()}/Models`;
  }

  // MARK: - Framework-Specific Paths

  /**
   * Get the folder for a specific framework
   * @param framework The ML framework
   * @returns Path to `Documents/RunAnywhere/Models/{framework}/`
   * @throws If models directory cannot be accessed
   */
  static getFrameworkDirectory(framework: InferenceFramework): string {
    return `${this.getModelsDirectory()}/${framework}`;
  }

  /**
   * Get the folder for a specific model within a framework
   * @param modelId The model identifier
   * @param framework The ML framework
   * @returns Path to `Documents/RunAnywhere/Models/{framework}/{modelId}/`
   * @throws If framework directory cannot be accessed
   */
  static getModelFolder(modelId: string, framework: InferenceFramework): string;
  /**
   * Get the folder for a model (legacy path without framework)
   * @param modelId The model identifier
   * @returns Path to `Documents/RunAnywhere/Models/{modelId}/`
   * @throws If models directory cannot be accessed
   */
  static getModelFolder(modelId: string): string;
  static getModelFolder(
    modelId: string,
    framework?: InferenceFramework
  ): string {
    if (framework !== undefined) {
      return `${this.getFrameworkDirectory(framework)}/${modelId}`;
    } else {
      return `${this.getModelsDirectory()}/${modelId}`;
    }
  }

  // MARK: - Model File Paths

  /**
   * Get the full path to a model file
   * @param modelId The model identifier
   * @param framework The ML framework
   * @param format The model file format
   * @returns Path to `Documents/RunAnywhere/Models/{framework}/{modelId}/{modelId}.{format}`
   * @throws If model folder cannot be accessed
   */
  static getModelFilePath(
    modelId: string,
    framework: InferenceFramework,
    format: ModelFormat
  ): string;
  /**
   * Get the full path to a model file (legacy path without framework)
   * @param modelId The model identifier
   * @param format The model file format
   * @returns Path to `Documents/RunAnywhere/Models/{modelId}/{modelId}.{format}`
   * @throws If model folder cannot be accessed
   */
  static getModelFilePath(modelId: string, format: ModelFormat): string;
  static getModelFilePath(
    modelId: string,
    frameworkOrFormat: InferenceFramework | ModelFormat,
    format?: ModelFormat
  ): string {
    if (format !== undefined) {
      // Three-parameter version: modelId, framework, format
      const framework = frameworkOrFormat as InferenceFramework;
      const fileName = `${modelId}.${format}`;
      return `${this.getModelFolder(modelId, framework)}/${fileName}`;
    } else {
      // Two-parameter version: modelId, format
      const modelFormat = frameworkOrFormat as ModelFormat;
      const fileName = `${modelId}.${modelFormat}`;
      return `${this.getModelFolder(modelId)}/${fileName}`;
    }
  }

  /**
   * Get the expected model path from components
   * @param modelId The model identifier
   * @param framework The ML framework (optional)
   * @param format The model file format
   * @returns Path to the expected model path
   * @throws If model folder cannot be accessed
   */
  static getExpectedModelPath(
    modelId: string,
    framework: InferenceFramework | null,
    format: ModelFormat
  ): string {
    if (framework) {
      if (isDirectoryBased(format)) {
        return this.getModelFolder(modelId, framework);
      }
      return this.getModelFilePath(modelId, framework, format);
    } else {
      if (isDirectoryBased(format)) {
        return this.getModelFolder(modelId);
      }
      return this.getModelFilePath(modelId, format);
    }
  }

  // MARK: - Other Directories

  /**
   * Get the cache directory
   * @returns Path to `Documents/RunAnywhere/Cache/`
   * @throws If base directory cannot be accessed
   */
  static getCacheDirectory(): string {
    return `${this.getBaseDirectory()}/Cache`;
  }

  /**
   * Get the temporary files directory
   * @returns Path to `Documents/RunAnywhere/Temp/`
   * @throws If base directory cannot be accessed
   */
  static getTempDirectory(): string {
    return `${this.getBaseDirectory()}/Temp`;
  }

  /**
   * Get the downloads directory
   * @returns Path to `Documents/RunAnywhere/Downloads/`
   * @throws If base directory cannot be accessed
   */
  static getDownloadsDirectory(): string {
    return `${this.getBaseDirectory()}/Downloads`;
  }

  // MARK: - Path Analysis

  /**
   * Extract model ID from a file path
   * @param path The file path
   * @returns The model ID if found, null otherwise
   */
  static extractModelId(path: string): string | null {
    const pathComponents = path.split('/').filter((c) => c.length > 0);

    // Check if this is a model in our framework structure
    const modelsIndex = pathComponents.indexOf('Models');
    if (modelsIndex === -1 || modelsIndex + 1 >= pathComponents.length) {
      return null;
    }

    const nextComponent = pathComponents[modelsIndex + 1];

    // Check if next component is a framework name
    const allFrameworks = Object.values(InferenceFramework);
    if (
      allFrameworks.includes(nextComponent as InferenceFramework) &&
      modelsIndex + 2 < pathComponents.length
    ) {
      // Framework structure: Models/framework/modelId
      return pathComponents[modelsIndex + 2];
    } else {
      // Direct model folder structure: Models/modelId
      return nextComponent;
    }
  }

  /**
   * Extract framework from a file path
   * @param path The file path
   * @returns The framework if found, null otherwise
   */
  static extractFramework(path: string): InferenceFramework | null {
    const pathComponents = path.split('/').filter((c) => c.length > 0);

    const modelsIndex = pathComponents.indexOf('Models');
    if (modelsIndex === -1 || modelsIndex + 1 >= pathComponents.length) {
      return null;
    }

    const nextComponent = pathComponents[modelsIndex + 1];

    // Check if next component is a framework name
    const allFrameworks = Object.values(InferenceFramework);
    if (allFrameworks.includes(nextComponent as InferenceFramework)) {
      return nextComponent as InferenceFramework;
    }

    return null;
  }

  /**
   * Check if a path is within the models directory
   * @param path The file path to check
   * @returns true if the path is within the models directory
   */
  static isModelPath(path: string): boolean {
    return path.includes('/Models/');
  }
}

// MARK: - ModelFormat Extensions

/**
 * Whether this format represents a directory-based model
 */
export function isDirectoryBased(format: ModelFormat): boolean {
  switch (format) {
    case ModelFormat.MLModel:
    case ModelFormat.MLPackage:
      return true;
    default:
      return false;
  }
}
