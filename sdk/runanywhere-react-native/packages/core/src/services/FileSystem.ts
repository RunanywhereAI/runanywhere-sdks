/**
 * FileSystem.ts
 *
 * File system service using react-native-fs for model downloads and storage.
 * Matches Swift SDK's path structure: Documents/RunAnywhere/Models/{framework}/{modelId}/
 */

import { Platform } from 'react-native';
import { SDKLogger } from '../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('FileSystem');

// Lazy-loaded native module getter to avoid initialization order issues
let _nativeModuleGetter: (() => { extractArchive: (archivePath: string, destPath: string) => Promise<boolean> }) | null = null;

function getNativeModule(): { extractArchive: (archivePath: string, destPath: string) => Promise<boolean> } | null {
  if (_nativeModuleGetter === null) {
    try {
      // Dynamic require to avoid circular dependency and initialization order issues
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      const { requireNativeModule, isNativeModuleAvailable } = require('../native/NativeRunAnywhereCore');
      if (isNativeModuleAvailable()) {
        _nativeModuleGetter = () => requireNativeModule();
      } else {
        logger.warning('Native module not available for archive extraction');
        return null;
      }
    } catch (e) {
      logger.error('Failed to load native module:', e);
      return null;
    }
  }
  return _nativeModuleGetter ? _nativeModuleGetter() : null;
}

// Try to import react-native-fs
let RNFS: typeof import('react-native-fs') | null = null;
try {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  RNFS = require('react-native-fs');
} catch {
  logger.warning('react-native-fs not installed, file operations will be limited');
}

// Try to import react-native-zip-archive
let ZipArchive: {
  unzip: (source: string, target: string) => Promise<string>;
  unzipWithPassword: (source: string, target: string, password: string) => Promise<string>;
  unzipAssets: (assetPath: string, target: string) => Promise<string>;
  subscribe: (callback: (event: { progress: number; filePath: string }) => void) => { remove: () => void };
} | null = null;
try {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  ZipArchive = require('react-native-zip-archive');
} catch {
  logger.warning('react-native-zip-archive not installed, archive extraction will be limited');
}

// Constants matching Swift SDK path structure
const RUN_ANYWHERE_DIR = 'RunAnywhere';
const MODELS_DIR = 'Models';

/**
 * Download progress information
 */
export interface DownloadProgress {
  bytesWritten: number;
  contentLength: number;
  progress: number;
}

/**
 * Archive types supported for extraction
 * Matches Swift SDK's ArchiveType enum
 */
export enum ArchiveType {
  Zip = 'zip',
  TarBz2 = 'tar.bz2',
  TarGz = 'tar.gz',
  TarXz = 'tar.xz',
}

/**
 * Describes the internal structure of an archive after extraction
 * Matches Swift SDK's ArchiveStructure enum
 */
export enum ArchiveStructure {
  SingleFileNested = 'singleFileNested',
  DirectoryBased = 'directoryBased',
  NestedDirectory = 'nestedDirectory',
  Unknown = 'unknown',
}

/**
 * Model artifact type - describes how a model is packaged
 * Matches Swift SDK's ModelArtifactType enum
 */
export type ModelArtifactType =
  | { type: 'singleFile' }
  | { type: 'archive'; archiveType: ArchiveType; structure: ArchiveStructure }
  | { type: 'multiFile'; files: string[] }
  | { type: 'custom'; strategyId: string }
  | { type: 'builtIn' };

/**
 * Extraction result
 */
export interface ExtractionResult {
  modelPath: string;
  extractedSize: number;
  fileCount: number;
}

/**
 * Infer archive type from URL
 */
function inferArchiveType(url: string): ArchiveType | null {
  const lowercased = url.toLowerCase();
  if (lowercased.includes('.tar.bz2') || lowercased.includes('.tbz2')) {
    return ArchiveType.TarBz2;
  }
  if (lowercased.includes('.tar.gz') || lowercased.includes('.tgz')) {
    return ArchiveType.TarGz;
  }
  if (lowercased.includes('.tar.xz') || lowercased.includes('.txz')) {
    return ArchiveType.TarXz;
  }
  if (lowercased.includes('.zip')) {
    return ArchiveType.Zip;
  }
  return null;
}

/**
 * Infer framework from file name/extension
 */
function inferFramework(fileName: string): string {
  const lower = fileName.toLowerCase();
  if (lower.includes('.gguf') || lower.includes('.bin')) {
    return 'LlamaCpp';
  }
  if (lower.includes('.onnx') || lower.includes('.tar') || lower.includes('.zip')) {
    return 'ONNX';
  }
  return 'LlamaCpp'; // Default
}

/**
 * Extract base model ID (remove extension)
 */
function getBaseModelId(modelId: string): string {
  return modelId
    .replace('.gguf', '')
    .replace('.onnx', '')
    .replace('.tar.bz2', '')
    .replace('.tar.gz', '')
    .replace('.zip', '')
    .replace('.bin', '');
}

/**
 * File system service for model management
 */
export const FileSystem = {
  /**
   * Check if react-native-fs is available
   */
  isAvailable(): boolean {
    return RNFS !== null;
  },

  /**
   * Get the base documents directory
   */
  getDocumentsDirectory(): string {
    if (!RNFS) {
      throw new Error('react-native-fs not installed');
    }
    return Platform.OS === 'android'
      ? RNFS.DocumentDirectoryPath
      : RNFS.DocumentDirectoryPath;
  },

  /**
   * Get the RunAnywhere base directory
   * Returns: Documents/RunAnywhere/
   */
  getRunAnywhereDirectory(): string {
    return `${this.getDocumentsDirectory()}/${RUN_ANYWHERE_DIR}`;
  },

  /**
   * Get the models directory
   * Returns: Documents/RunAnywhere/Models/
   */
  getModelsDirectory(): string {
    return `${this.getRunAnywhereDirectory()}/${MODELS_DIR}`;
  },

  /**
   * Get framework directory
   * Returns: Documents/RunAnywhere/Models/{framework}/
   */
  getFrameworkDirectory(framework: string): string {
    return `${this.getModelsDirectory()}/${framework}`;
  },

  /**
   * Get model folder
   * Returns: Documents/RunAnywhere/Models/{framework}/{modelId}/
   */
  getModelFolder(modelId: string, framework?: string): string {
    const fw = framework || inferFramework(modelId);
    const baseId = getBaseModelId(modelId);
    return `${this.getFrameworkDirectory(fw)}/${baseId}`;
  },

  /**
   * Get model file path
   * For LlamaCpp: Documents/RunAnywhere/Models/LlamaCpp/{modelId}/{modelId}.gguf
   * For ONNX: Documents/RunAnywhere/Models/ONNX/{modelId}/ (folder, checking for nested dirs)
   */
  async getModelPath(modelId: string, framework?: string): Promise<string> {
    const fw = framework || inferFramework(modelId);
    const folder = this.getModelFolder(modelId, fw);
    const baseId = getBaseModelId(modelId);

    if (fw === 'LlamaCpp') {
      // Single file model
      const ext = modelId.includes('.gguf')
        ? '.gguf'
        : modelId.includes('.bin')
          ? '.bin'
          : '.gguf';
      return `${folder}/${baseId}${ext}`;
    }

    // For ONNX, check if the model is in a nested directory structure
    if (RNFS) {
      try {
        const exists = await RNFS.exists(folder);
        if (exists) {
          // Find the actual model path (handles nested directory structures)
          const modelPath = await this.findModelPathAfterExtraction(folder);
          return modelPath;
        }
      } catch {
        // Fall through to return the default folder
      }
    }

    // Directory-based model (ONNX)
    return folder;
  },

  /**
   * Check if a model exists
   * For LlamaCpp: checks if the .gguf file exists
   * For ONNX: checks if the folder has .onnx files (extracted archive)
   */
  async modelExists(modelId: string, framework?: string): Promise<boolean> {
    if (!RNFS) return false;

    const fw = framework || inferFramework(modelId);
    const folder = this.getModelFolder(modelId, fw);

    try {
      const exists = await RNFS.exists(folder);
      if (!exists) return false;

      // Check if folder has contents
      const files = await RNFS.readDir(folder);
      if (files.length === 0) return false;

      if (fw === 'ONNX') {
        // For ONNX, we need to check if there are actual model files (not just an archive)
        // ONNX models should have .onnx files after extraction
        const hasOnnxFiles = await this.hasModelFiles(folder);
        return hasOnnxFiles;
      }

      return true;
    } catch {
      return false;
    }
  },

  /**
   * Recursively check if a folder contains model files
   */
  async hasModelFiles(folder: string): Promise<boolean> {
    if (!RNFS) return false;

    try {
      const contents = await RNFS.readDir(folder);

      for (const item of contents) {
        if (item.isFile()) {
          const name = item.name.toLowerCase();
          // Check for actual model files, not archive files
          if (name.endsWith('.onnx') || name.endsWith('.bin') || name.endsWith('.txt')) {
            return true;
          }
        } else if (item.isDirectory()) {
          // Check nested directories
          const hasFiles = await this.hasModelFiles(item.path);
          if (hasFiles) return true;
        }
      }

      return false;
    } catch {
      return false;
    }
  },

  /**
   * Create directory if it doesn't exist
   */
  async ensureDirectory(path: string): Promise<void> {
    if (!RNFS) return;

    try {
      const exists = await RNFS.exists(path);
      if (!exists) {
        await RNFS.mkdir(path);
      }
    } catch (error) {
      logger.error(`Failed to create directory: ${path}`, error);
    }
  },

  /**
   * Download a model file
   */
  async downloadModel(
    modelId: string,
    url: string,
    onProgress?: (progress: DownloadProgress) => void,
    framework?: string
  ): Promise<string> {
    if (!RNFS) {
      throw new Error('react-native-fs not installed');
    }

    const fw = framework || inferFramework(modelId);
    const folder = this.getModelFolder(modelId, fw);
    const baseId = getBaseModelId(modelId);

    // Ensure directory structure exists
    await this.ensureDirectory(this.getRunAnywhereDirectory());
    await this.ensureDirectory(this.getModelsDirectory());
    await this.ensureDirectory(this.getFrameworkDirectory(fw));
    await this.ensureDirectory(folder);

    // Determine destination path
    let destPath: string;
    if (fw === 'LlamaCpp') {
      const ext =
        modelId.includes('.gguf') || url.includes('.gguf')
          ? '.gguf'
          : modelId.includes('.bin') || url.includes('.bin')
            ? '.bin'
            : '.gguf';
      destPath = `${folder}/${baseId}${ext}`;
    } else {
      // For archives, download to temp first
      const tempName = `${baseId}_${Date.now()}.tmp`;
      destPath = `${RNFS.CachesDirectoryPath}/${tempName}`;
    }

    logger.info(`Downloading model: ${modelId}`);
    logger.debug(`URL: ${url}`);
    logger.debug(`Destination: ${destPath}`);

    // Check if already exists
    const exists = await RNFS.exists(destPath);
    if (exists && fw === 'LlamaCpp') {
      logger.info(`Model already exists: ${destPath}`);
      return destPath;
    }

    // Download with progress
    const downloadResult = RNFS.downloadFile({
      fromUrl: url,
      toFile: destPath,
      background: true,
      discretionary: true,
      cacheable: false,
      progressInterval: 300,
      progressDivider: 1,
      begin: (res) => {
        logger.info(
          `Download started: ${res.contentLength} bytes, status: ${res.statusCode}`
        );
      },
      progress: (res) => {
        const progress = res.contentLength > 0
          ? res.bytesWritten / res.contentLength
          : 0;

        if (onProgress) {
          onProgress({
            bytesWritten: res.bytesWritten,
            contentLength: res.contentLength,
            progress,
          });
        }
      },
    });

    const result = await downloadResult.promise;

    if (result.statusCode !== 200) {
      throw new Error(`Download failed with status: ${result.statusCode}`);
    }

    logger.info(`Download completed: ${result.bytesWritten} bytes`);

    // For ONNX archives, extract to final location
    const archiveType = inferArchiveType(url);
    if (fw === 'ONNX' && archiveType !== null) {
      logger.info(`Extracting ${archiveType} archive...`);

      try {
        const extractionResult = await this.extractArchive(destPath, folder, archiveType);
        logger.info(`Extraction completed: ${extractionResult.fileCount} files, ${extractionResult.extractedSize} bytes`);

        // Clean up the temporary archive file
        await RNFS.unlink(destPath);

        // Return the extracted folder path
        destPath = extractionResult.modelPath;
      } catch (extractError) {
        logger.error(`Archive extraction failed: ${extractError}`);
        // Clean up temp file on failure
        try {
          await RNFS.unlink(destPath);
        } catch {
          // Ignore cleanup errors
        }
        throw new Error(`Archive extraction failed: ${extractError}`);
      }
    }

    return destPath;
  },

  /**
   * Extract an archive to a destination folder
   * Uses native extraction via the core module (iOS: ArchiveUtility, Android: native extraction)
   */
  async extractArchive(
    archivePath: string,
    destinationFolder: string,
    archiveType: ArchiveType,
    onProgress?: (progress: number) => void
  ): Promise<ExtractionResult> {
    if (!RNFS) {
      throw new Error('react-native-fs not installed');
    }

    logger.info(`Extracting archive: ${archivePath}`);
    logger.info(`Archive type: ${archiveType}`);
    logger.info(`Destination: ${destinationFolder}`);

    // Ensure destination exists
    await this.ensureDirectory(destinationFolder);

    // Try native extraction first (supports tar.gz, tar.bz2, zip)
    try {
      const native = getNativeModule();
      if (!native) {
        throw new Error('Native module not available');
      }

      logger.info('Using native archive extraction...');
      const success = await native.extractArchive(archivePath, destinationFolder);

      if (!success) {
        throw new Error('Native extraction returned false');
      }

      logger.info('Native extraction completed successfully');
    } catch (nativeError) {
      logger.warning(`Native extraction failed: ${nativeError}, trying fallback...`);

      // Fallback to react-native-zip-archive for ZIP files only
      if (archiveType === ArchiveType.Zip && ZipArchive) {
        logger.info('Falling back to react-native-zip-archive for ZIP...');

        let subscription: { remove: () => void } | null = null;
        if (onProgress) {
          subscription = ZipArchive.subscribe(({ progress }) => {
            onProgress(progress);
          });
        }

        try {
          await ZipArchive.unzip(archivePath, destinationFolder);
        } finally {
          if (subscription) {
            subscription.remove();
          }
        }
      } else if (archiveType === ArchiveType.TarGz || archiveType === ArchiveType.TarBz2) {
        // No fallback for tar archives - native is required
        throw new Error(
          `Archive extraction failed for ${archiveType}. Native extraction is required for tar archives. Error: ${nativeError}`
        );
      } else {
        throw new Error(`Archive extraction failed: ${nativeError}`);
      }
    }

    // After extraction, find the actual model path
    // ONNX models are typically nested in a directory with the same name
    const modelPath = await this.findModelPathAfterExtraction(destinationFolder);

    // Calculate extraction stats
    const stats = await this.calculateExtractionStats(destinationFolder);

    return {
      modelPath,
      extractedSize: stats.totalSize,
      fileCount: stats.fileCount,
    };
  },

  /**
   * Find the actual model path after extraction
   * Handles nested directory structures common in ONNX archives
   */
  async findModelPathAfterExtraction(extractedFolder: string): Promise<string> {
    if (!RNFS) {
      return extractedFolder;
    }

    try {
      const contents = await RNFS.readDir(extractedFolder);

      // If there's exactly one directory and no files, it might be a nested structure
      const directories = contents.filter(item => item.isDirectory());
      const files = contents.filter(item => item.isFile());

      if (directories.length === 1 && files.length === 0) {
        // Nested directory - the actual model is inside
        const nestedDir = directories[0];
        logger.info(`Found nested directory structure: ${nestedDir.name}`);
        return nestedDir.path;
      }

      // Otherwise, the extracted folder contains the model directly
      return extractedFolder;
    } catch (error) {
      logger.error(`Error finding model path: ${error}`);
      return extractedFolder;
    }
  },

  /**
   * Calculate extraction statistics
   */
  async calculateExtractionStats(folder: string): Promise<{ totalSize: number; fileCount: number }> {
    if (!RNFS) {
      return { totalSize: 0, fileCount: 0 };
    }

    let totalSize = 0;
    let fileCount = 0;

    const processDir = async (dir: string) => {
      try {
        const contents = await RNFS!.readDir(dir);
        for (const item of contents) {
          if (item.isFile()) {
            totalSize += item.size;
            fileCount++;
          } else if (item.isDirectory()) {
            await processDir(item.path);
          }
        }
      } catch {
        // Ignore errors
      }
    };

    await processDir(folder);
    return { totalSize, fileCount };
  },

  /**
   * Delete a model
   */
  async deleteModel(modelId: string, framework?: string): Promise<boolean> {
    if (!RNFS) return false;

    const fw = framework || inferFramework(modelId);
    const folder = this.getModelFolder(modelId, fw);

    try {
      const exists = await RNFS.exists(folder);
      if (exists) {
        await RNFS.unlink(folder);
        return true;
      }
      return false;
    } catch (error) {
      logger.error(`Failed to delete model: ${modelId}`, error);
      return false;
    }
  },

  /**
   * Get available disk space in bytes
   */
  async getAvailableDiskSpace(): Promise<number> {
    if (!RNFS) return 0;

    try {
      const info = await RNFS.getFSInfo();
      return info.freeSpace;
    } catch {
      return 0;
    }
  },

  /**
   * Get total disk space in bytes
   */
  async getTotalDiskSpace(): Promise<number> {
    if (!RNFS) return 0;

    try {
      const info = await RNFS.getFSInfo();
      return info.totalSpace;
    } catch {
      return 0;
    }
  },

  /**
   * Read a file as string
   */
  async readFile(path: string): Promise<string> {
    if (!RNFS) {
      throw new Error('react-native-fs not installed');
    }
    return RNFS.readFile(path, 'utf8');
  },

  /**
   * Write a string to a file
   */
  async writeFile(path: string, content: string): Promise<void> {
    if (!RNFS) {
      throw new Error('react-native-fs not installed');
    }
    await RNFS.writeFile(path, content, 'utf8');
  },

  /**
   * Check if a file exists
   */
  async fileExists(path: string): Promise<boolean> {
    if (!RNFS) return false;
    return RNFS.exists(path);
  },

  /**
   * Delete a file
   */
  async deleteFile(path: string): Promise<boolean> {
    if (!RNFS) return false;

    try {
      await RNFS.unlink(path);
      return true;
    } catch {
      return false;
    }
  },
};

export default FileSystem;
