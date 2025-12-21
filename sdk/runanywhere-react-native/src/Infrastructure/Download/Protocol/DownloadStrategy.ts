/**
 * DownloadStrategy.ts
 *
 * Protocol for custom download strategies provided by host app
 * Allows extending download behavior without modifying core SDK logic
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Download/Protocol/DownloadStrategy.swift
 */

import type { ModelInfo } from '../../../Core/Models/Model/ModelInfo';

/**
 * Protocol for custom download strategies provided by host app
 * Allows extending download behavior without modifying core SDK logic
 */
export interface DownloadStrategy {
  /**
   * Check if this strategy can handle the given model
   * @param model The model to check
   * @returns True if this strategy can handle the model
   */
  canHandle(model: ModelInfo): boolean;

  /**
   * Download the model (can be multi-file, ZIP, etc.)
   * @param model The model to download
   * @param destinationFolder Where to save the downloaded files
   * @param progressHandler Optional progress callback (0.0 to 1.0)
   * @returns Path to the downloaded model folder
   * @throws Error if download fails
   */
  download(
    model: ModelInfo,
    destinationFolder: string,
    progressHandler?: (progress: number) => void
  ): Promise<string>;
}
