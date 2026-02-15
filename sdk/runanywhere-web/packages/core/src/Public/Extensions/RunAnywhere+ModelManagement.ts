/**
 * RunAnywhere Web SDK - Model Management Extension
 *
 * Handles model downloading, storage, and lifecycle in the browser.
 * Uses Fetch API for downloads and Emscripten FS for storage.
 *
 * Mirrors: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/
 *          ModelManagement/RunAnywhere+ModelManagement.swift
 */

import { RunAnywhere } from '../RunAnywhere';
import { WASMBridge } from '../../Foundation/WASMBridge';
import { SDKError } from '../../Foundation/ErrorTypes';
import { SDKLogger } from '../../Foundation/SDKLogger';
import { EventBus } from '../../Foundation/EventBus';
import { SDKEventType } from '../../types/enums';

const logger = new SDKLogger('ModelManagement');

/** Download progress callback */
export type DownloadProgressCallback = (
  bytesDownloaded: number,
  totalBytes: number,
  progress: number,
) => void;

/** Model download options */
export interface ModelDownloadOptions {
  /** Override destination path (default: /models/<filename>) */
  destPath?: string;
  /** Progress callback */
  onProgress?: DownloadProgressCallback;
  /** AbortController signal for cancellation */
  signal?: AbortSignal;
}

/** Models directory in Emscripten FS */
const MODELS_DIR = '/models';

export const ModelManagement = {
  /**
   * Download a model file from a URL to Emscripten FS.
   *
   * Uses Fetch API with ReadableStream for progress tracking.
   * The downloaded file is stored in the Emscripten virtual filesystem
   * and can be loaded by llama.cpp / whisper.cpp directly.
   *
   * @param url - URL to download the model from
   * @param modelId - Identifier for the model
   * @param options - Download options (progress callback, dest path, etc.)
   * @returns Local path where model was saved (in Emscripten FS)
   */
  async downloadModel(
    url: string,
    modelId: string,
    options: ModelDownloadOptions = {},
  ): Promise<string> {
    if (!RunAnywhere.isInitialized) {
      throw SDKError.notInitialized();
    }

    const bridge = WASMBridge.shared;
    const m = bridge.module;

    // Determine destination path
    const filename = url.split('/').pop() ?? `${modelId}.gguf`;
    const destPath = options.destPath ?? `${MODELS_DIR}/${filename}`;

    logger.info(`Downloading model: ${modelId} from ${url}`);
    EventBus.shared.emit('model.downloadStarted', SDKEventType.Model, { modelId, url });

    // Ensure models directory exists
    try {
      m.FS.mkdir(MODELS_DIR);
    } catch {
      // Directory already exists
    }

    try {
      const response = await fetch(url, { signal: options.signal });
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const contentLength = parseInt(response.headers.get('content-length') ?? '0', 10);
      const reader = response.body?.getReader();
      if (!reader) {
        throw new Error('ReadableStream not supported');
      }

      const chunks: Uint8Array[] = [];
      let downloaded = 0;

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        chunks.push(value);
        downloaded += value.length;

        const progress = contentLength > 0 ? downloaded / contentLength : 0;

        options.onProgress?.(downloaded, contentLength, progress);

        EventBus.shared.emit('model.downloadProgress', SDKEventType.Model, {
          modelId,
          progress,
          bytesDownloaded: downloaded,
          totalBytes: contentLength,
        });
      }

      // Combine chunks
      const totalData = new Uint8Array(downloaded);
      let offset = 0;
      for (const chunk of chunks) {
        totalData.set(chunk, offset);
        offset += chunk.length;
      }

      // Write to Emscripten FS
      m.FS.writeFile(destPath, totalData);

      // Verify
      const stat = m.FS.stat(destPath);
      logger.info(`Model downloaded: ${modelId} (${(stat.size / 1024 / 1024).toFixed(1)} MB) -> ${destPath}`);

      EventBus.shared.emit('model.downloadCompleted', SDKEventType.Model, {
        modelId,
        localPath: destPath,
        sizeBytes: stat.size,
      });

      return destPath;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logger.error(`Download failed for ${modelId}: ${message}`);

      EventBus.shared.emit('model.downloadFailed', SDKEventType.Model, {
        modelId,
        error: message,
      });

      throw error;
    }
  },

  /**
   * Check if a model file exists in Emscripten FS.
   */
  isModelDownloaded(path: string): boolean {
    try {
      const m = WASMBridge.shared.module;
      return m.FS.analyzePath(path).exists;
    } catch {
      return false;
    }
  },

  /**
   * Delete a downloaded model from Emscripten FS.
   */
  deleteModel(path: string): void {
    try {
      const m = WASMBridge.shared.module;
      m.FS.unlink(path);
      logger.info(`Model deleted: ${path}`);
    } catch (error) {
      logger.error(`Failed to delete model: ${error}`);
    }
  },

  /**
   * Get the size of a downloaded model file.
   * @returns Size in bytes, or 0 if not found
   */
  getModelSize(path: string): number {
    try {
      const m = WASMBridge.shared.module;
      return m.FS.stat(path).size;
    } catch {
      return 0;
    }
  },

  /**
   * List all model files in the models directory.
   */
  listDownloadedModels(): string[] {
    // Note: Emscripten FS readdir requires node-like API
    // For now, return empty -- this will be enhanced with OPFS in Phase 5
    return [];
  },
};
