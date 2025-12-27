/**
 * ArchiveManager.ts
 *
 * Archive extraction utilities using react-native-zip-archive for ZIP files
 * and Nitrogen native bridge for tar.bz2/tar.gz archives.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Storage/FileSystem/ArchiveExtractor.swift
 */

import { SDKLogger } from '../Logging/Logger/SDKLogger';
import { NativeRunAnywhere } from '@runanywhere/native';

// Dynamic import for optional peer dependency
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let ZipArchive: any = null;

try {
  ZipArchive = require('react-native-zip-archive');
} catch {
  // Package not installed
}

const logger = new SDKLogger('ArchiveManager');

/**
 * Archive extraction result
 */
export interface ArchiveExtractionResult {
  success: boolean;
  extractedPath: string | null;
  fileCount?: number;
  error?: string;
}

/**
 * Supported archive formats
 */
export type ArchiveFormat = 'zip' | 'tar.gz' | 'tar.bz2' | 'tgz' | 'unknown';

/**
 * Archive Manager for extracting compressed files.
 *
 * Uses react-native-zip-archive for ZIP files and the Nitrogen native
 * bridge (via runanywhere-core) for tar.bz2 and tar.gz archives.
 */
export class ArchiveManager {
  private static _instance: ArchiveManager | null = null;

  /**
   * Get shared instance
   */
  public static get shared(): ArchiveManager {
    if (!ArchiveManager._instance) {
      ArchiveManager._instance = new ArchiveManager();
    }
    return ArchiveManager._instance;
  }

  /**
   * Check if archive extraction is available
   */
  public isAvailable(): boolean {
    // Nitrogen bridge always available for tar archives
    // ZipArchive optional for ZIP files
    return true;
  }

  /**
   * Check if ZIP extraction is available
   */
  public isZipAvailable(): boolean {
    return ZipArchive !== null;
  }

  /**
   * Detect archive format from file path
   */
  public detectFormat(filePath: string): ArchiveFormat {
    const path = filePath.toLowerCase();

    if (path.endsWith('.zip')) {
      return 'zip';
    }
    if (path.endsWith('.tar.gz') || path.endsWith('.tgz')) {
      return 'tar.gz';
    }
    if (path.endsWith('.tar.bz2') || path.endsWith('.bz2')) {
      return 'tar.bz2';
    }

    return 'unknown';
  }

  /**
   * Check if a file is an archive
   */
  public isArchive(filePath: string): boolean {
    return this.detectFormat(filePath) !== 'unknown';
  }

  /**
   * Extract an archive to a destination directory
   *
   * @param archivePath - Path to the archive file
   * @param destPath - Destination directory (will be created if doesn't exist)
   * @param onProgress - Optional progress callback (0.0 to 1.0)
   */
  public async extract(
    archivePath: string,
    destPath: string,
    onProgress?: (progress: number) => void
  ): Promise<ArchiveExtractionResult> {
    const format = this.detectFormat(archivePath);

    logger.debug('Extracting archive', { archivePath, destPath, format });

    try {
      switch (format) {
        case 'zip':
          return await this.extractZip(archivePath, destPath, onProgress);

        case 'tar.gz':
        case 'tar.bz2':
        case 'tgz':
          return await this.extractTar(archivePath, destPath, onProgress);

        default:
          return {
            success: false,
            extractedPath: null,
            error: `Unsupported archive format: ${format}`,
          };
      }
    } catch (error) {
      const errorMessage =
        error instanceof Error ? error.message : String(error);
      logger.error('Archive extraction failed', {
        archivePath,
        error: errorMessage,
      });

      return {
        success: false,
        extractedPath: null,
        error: errorMessage,
      };
    }
  }

  /**
   * Extract a ZIP archive using react-native-zip-archive
   */
  private async extractZip(
    archivePath: string,
    destPath: string,
    onProgress?: (progress: number) => void
  ): Promise<ArchiveExtractionResult> {
    if (!ZipArchive) {
      return {
        success: false,
        extractedPath: null,
        error:
          'ZIP extraction requires react-native-zip-archive. Install it with: npm install react-native-zip-archive',
      };
    }

    try {
      // Subscribe to progress events
      let subscription: (() => void) | null = null;
      if (onProgress && ZipArchive.subscribe) {
        subscription = ZipArchive.subscribe(
          ({ progress }: { progress: number }) => {
            onProgress(progress);
          }
        );
      }

      // Extract the archive
      const extractedPath = await ZipArchive.unzip(archivePath, destPath);

      // Unsubscribe from progress events
      if (subscription) {
        subscription();
      }

      onProgress?.(1.0);

      logger.debug('ZIP extraction completed', { extractedPath });

      return {
        success: true,
        extractedPath,
      };
    } catch (error) {
      const errorMessage =
        error instanceof Error ? error.message : String(error);

      return {
        success: false,
        extractedPath: null,
        error: `ZIP extraction failed: ${errorMessage}`,
      };
    }
  }

  /**
   * Extract a tar archive using Nitrogen native bridge
   *
   * The runanywhere-core C library handles tar.bz2 and tar.gz extraction
   * via libarchive (iOS) or Apache Commons Compress (Android).
   */
  private async extractTar(
    archivePath: string,
    destPath: string,
    onProgress?: (progress: number) => void
  ): Promise<ArchiveExtractionResult> {
    try {
      // Use Nitrogen native bridge for tar extraction
      // This calls ra_extract_archive in runanywhere-core
      const success = await NativeRunAnywhere.extractArchive(
        archivePath,
        destPath
      );

      if (success) {
        onProgress?.(1.0);

        logger.debug('TAR extraction completed', { destPath });

        return {
          success: true,
          extractedPath: destPath,
        };
      } else {
        const lastError = await NativeRunAnywhere.getLastError();
        return {
          success: false,
          extractedPath: null,
          error: lastError || 'TAR extraction failed',
        };
      }
    } catch (error) {
      const errorMessage =
        error instanceof Error ? error.message : String(error);

      return {
        success: false,
        extractedPath: null,
        error: `TAR extraction failed: ${errorMessage}`,
      };
    }
  }

  /**
   * Create a ZIP archive from files/directories
   *
   * @param sourcePath - Source file or directory to compress
   * @param destPath - Destination ZIP file path
   */
  public async createZip(
    sourcePath: string,
    destPath: string
  ): Promise<boolean> {
    if (!ZipArchive) {
      logger.warning('ZIP creation requires react-native-zip-archive package');
      return false;
    }

    try {
      await ZipArchive.zip(sourcePath, destPath);
      logger.debug('ZIP created', { sourcePath, destPath });
      return true;
    } catch (error) {
      const errorMessage =
        error instanceof Error ? error.message : String(error);
      logger.error('ZIP creation failed', { error: errorMessage });
      return false;
    }
  }

  /**
   * Get contents of a ZIP archive without extracting
   */
  public async getZipContents(archivePath: string): Promise<string[] | null> {
    if (!ZipArchive || !ZipArchive.getUncompressedSize) {
      return null;
    }

    try {
      // react-native-zip-archive doesn't have a direct list method
      // but we can check if archive is valid
      const size = await ZipArchive.getUncompressedSize(archivePath);
      if (size > 0) {
        // Archive is valid but we can't list contents without extracting
        return [];
      }
      return null;
    } catch {
      return null;
    }
  }
}

/**
 * Convenience function to extract an archive
 */
export async function extractArchive(
  archivePath: string,
  destPath: string,
  onProgress?: (progress: number) => void
): Promise<ArchiveExtractionResult> {
  return ArchiveManager.shared.extract(archivePath, destPath, onProgress);
}

/**
 * Convenience function to check if a file is an archive
 */
export function isArchive(filePath: string): boolean {
  return ArchiveManager.shared.isArchive(filePath);
}

/**
 * Convenience function to detect archive format
 */
export function detectArchiveFormat(filePath: string): ArchiveFormat {
  return ArchiveManager.shared.detectFormat(filePath);
}
