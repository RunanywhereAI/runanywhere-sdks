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
      logger.error('Failed to load native module:', { error: e });
      return null;
    }
  }
  return _nativeModuleGetter ? _nativeModuleGetter() : null;
}

// Types for react-native-fs (defined locally to avoid module resolution issues)
interface RNFSDownloadBeginCallbackResult {
  jobId: number;
  statusCode: number;
  contentLength: number;
  headers: Record<string, string>;
}

interface RNFSDownloadProgressCallbackResult {
  jobId: number;
  contentLength: number;
  bytesWritten: number;
}

interface RNFSStatResult {
  name: string;
  path: string;
  size: number;
  mode: number;
  ctime: number;
  mtime: number;
  isFile: () => boolean;
  isDirectory: () => boolean;
}

interface RNFSDownloadResult {
  jobId: number;
  statusCode: number;
  bytesWritten: number;
}

interface RNFSDownloadFileOptions {
  fromUrl: string;
  toFile: string;
  headers?: Record<string, string>;
  background?: boolean;
  progressDivider?: number;
  begin?: (res: RNFSDownloadBeginCallbackResult) => void;
  progress?: (res: RNFSDownloadProgressCallbackResult) => void;
  resumable?: () => void;
  connectionTimeout?: number;
  readTimeout?: number;
}

interface RNFSModule {
  DocumentDirectoryPath: string;
  CachesDirectoryPath: string;
  exists: (path: string) => Promise<boolean>;
  mkdir: (path: string, options?: { NSURLIsExcludedFromBackupKey?: boolean }) => Promise<void>;
  readDir: (path: string) => Promise<RNFSStatResult[]>;
  readFile: (path: string, encoding?: string) => Promise<string>;
  writeFile: (path: string, contents: string, encoding?: string) => Promise<void>;
  moveFile: (source: string, dest: string) => Promise<void>;
  copyFile: (source: string, dest: string) => Promise<void>;
  unlink: (path: string) => Promise<void>;
  stat: (path: string) => Promise<RNFSStatResult>;
  getFSInfo: () => Promise<{ totalSpace: number; freeSpace: number }>;
  downloadFile: (options: RNFSDownloadFileOptions) => { jobId: number; promise: Promise<RNFSDownloadResult> };
  stopDownload: (jobId: number) => void;
}

// Try to import react-native-fs
let RNFS: RNFSModule | null = null;
try {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  RNFS = require('react-native-fs');
} catch {
  logger.warning('react-native-fs not installed, file operations will be limited');
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
 * Check if a URL points to an archive that needs extraction.
 * C++ handles actual format detection via rac_detect_archive_type().
 */
function isArchiveUrl(url: string): boolean {
  const lowercased = url.toLowerCase();
  return (
    lowercased.includes('.tar.bz2') ||
    lowercased.includes('.tbz2') ||
    lowercased.includes('.tar.gz') ||
    lowercased.includes('.tgz') ||
    lowercased.includes('.tar.xz') ||
    lowercased.includes('.txz') ||
    lowercased.includes('.zip')
  );
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

    // Directory-based model (ONNX) — return the folder
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
        // For ONNX, directory has contents — model is present
        return true;
      }

      return true;
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
      logger.error(`Failed to create directory: ${path}`, { error });
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
    const needsExtraction = isArchiveUrl(url);
    if (fw === 'LlamaCpp' && !needsExtraction) {
      // Single GGUF/BIN file (not an archive)
      const ext =
        modelId.includes('.gguf') || url.includes('.gguf')
          ? '.gguf'
          : modelId.includes('.bin') || url.includes('.bin')
            ? '.bin'
            : '.gguf';
      destPath = `${folder}/${baseId}${ext}`;
    } else if (fw === 'ONNX' && !needsExtraction) {
      // ONNX single-file model (.onnx)
      const ext = modelId.includes('.onnx') || url.includes('.onnx') ? '.onnx' : '';
      destPath = `${folder}/${baseId}${ext}`;
    } else {
      // For archives (ONNX or LlamaCpp VLM tar.gz), download to temp first
      const tempName = `${baseId}_${Date.now()}.tmp`;
      destPath = `${RNFS.CachesDirectoryPath}/${tempName}`;
    }

    logger.info(`Downloading model: ${modelId}`);
    logger.debug(`URL: ${url}`);
    logger.debug(`Destination: ${destPath}`);

    // Check if already exists
    const exists = await RNFS.exists(destPath);
    if (exists && (fw === 'LlamaCpp' || (fw === 'ONNX' && !needsExtraction))) {
      logger.info(`Model already exists: ${destPath}`);
      return destPath;
    }

    // Download with progress
    const downloadResult = RNFS.downloadFile({
      fromUrl: url,
      toFile: destPath,
      background: true,
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

    // For archives (ONNX or LlamaCpp VLM), extract to final location
    if (needsExtraction) {
      logger.info(`Extracting archive for ${fw}...`);

      try {
        const modelPath = await this.extractArchive(destPath, folder);
        logger.info(`Extraction completed, model at: ${modelPath}`);

        // Clean up the temporary archive file
        await RNFS.unlink(destPath);

        destPath = modelPath;
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
   * Extract an archive to a destination folder.
   * Uses native C++ extraction via libarchive (auto-detects format).
   * Returns the extracted model path.
   */
  async extractArchive(
    archivePath: string,
    destinationFolder: string,
  ): Promise<string> {
    if (!RNFS) {
      throw new Error('react-native-fs not installed');
    }

    logger.info(`Extracting archive: ${archivePath}`);
    logger.info(`Destination: ${destinationFolder}`);

    // Ensure destination exists
    await this.ensureDirectory(destinationFolder);

    // Use native C++ extraction (libarchive) — auto-detects all formats
    const native = getNativeModule();
    if (!native) {
      throw new Error('Native module not available');
    }

    const success = await native.extractArchive(archivePath, destinationFolder);

    if (!success) {
      throw new Error('Native extraction failed');
    }

    logger.info('Native extraction completed successfully');

    // C++ extraction handles format detection and path finding.
    // Return the destination folder as the model path.
    return destinationFolder;
  },

  /**
   * Find mmproj file in same directory as model (for VLM models)
   * Returns path to mmproj file if found, undefined otherwise
   */
  async findMmprojForModel(modelPath: string): Promise<string | undefined> {
    if (!RNFS) {
      return undefined;
    }

    try {
      // Get directory containing the model
      const directory = modelPath.substring(0, modelPath.lastIndexOf('/'));
      const contents = await RNFS.readDir(directory);

      // Look for mmproj files
      for (const item of contents) {
        if (item.isFile() && item.name.endsWith('.gguf') && item.name.includes('mmproj')) {
          logger.info(`Found mmproj file: ${item.name}`);
          return item.path;
        }
      }

      logger.info('No mmproj file found - VLM backend will auto-detect if needed');
      return undefined;
    } catch (error) {
      logger.warning(`Error finding mmproj file: ${error}`);
      return undefined;
    }
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
      logger.error(`Failed to delete model: ${modelId}`, { error });
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
   * Check if a directory exists
   */
  async directoryExists(path: string): Promise<boolean> {
    if (!RNFS) return false;
    try {
      const exists = await RNFS.exists(path);
      if (!exists) return false;
      const stat = await RNFS.stat(path);
      return stat.isDirectory();
    } catch {
      return false;
    }
  },

  /**
   * Get the cache directory path
   */
  getCacheDirectory(): string {
    if (!RNFS) return '';
    return RNFS.CachesDirectoryPath;
  },

  /**
   * List contents of a directory
   */
  async listDirectory(dirPath: string): Promise<string[]> {
    if (!RNFS) return [];

    try {
      const exists = await RNFS.exists(dirPath);
      if (!exists) return [];

      const contents = await RNFS.readDir(dirPath);
      return contents.map((item) => item.name);
    } catch {
      return [];
    }
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
