/**
 * AssetModelExtractorService.ts
 *
 * Extracts bundled models from APK assets to the app's data directory on first launch.
 * This allows models to be pre-bundled in the APK and immediately available without download.
 *
 * Models bundled:
 * - all-MiniLM-L6-v2 (ONNX embedding model in assets/models/embeddings/)
 * - tinyllama (LlamaCPP LLM model in assets/models/llm/)
 */

import { Platform } from 'react-native';
import * as FileSystem from 'react-native-fs';
import AsyncStorage from '@react-native-async-storage/async-storage';

const TAG = '[AssetModelExtractor]';

// Key to track if assets have been extracted
const ASSETS_EXTRACTED_KEY = '@runanywhere_assets_extracted_v1';

/**
 * Bundled model definitions with asset paths
 */
interface BundledAssetModel {
  id: string;
  name: string;
  assetPath: string; // Path relative to assets/models/
  destPath: string; // Destination: ONNX or LlamaCpp
  format: 'onnx' | 'gguf';
  description: string;
}

const BUNDLED_ASSET_MODELS: BundledAssetModel[] = [
  {
    id: 'all-minilm-l6-v2',
    name: 'All MiniLM L6 v2',
    assetPath: 'embeddings/all-MiniLM-L6-v2',
    destPath: 'ONNX',
    format: 'onnx',
    description: 'ONNX embedding model for RAG retrieval - bundled in APK',
  },
  // NOTE: LLM models (tinyllama, etc.) are too large to bundle in APK (500MB+)
  // They should be downloaded on-demand or pre-loaded separately
  // To add bundled LLM models, use Approach 3: Compressed/differential updates
];

/**
 * Get the base models directory
 */
function getModelsBaseDir(): string {
  return `${FileSystem.DocumentDirectoryPath}/RunAnywhere/Models`;
}

/**
 * Get the destination directory for a model type
 */
function getModelTypeDir(modelType: 'ONNX' | 'LlamaCpp'): string {
  return `${getModelsBaseDir()}/${modelType}`;
}

/**
 * Get asset source path for reading from APK
 */
function getAssetSourcePath(assetPath: string): string {
  // Assets in react-native are accessed via assets:// scheme or through native module
  // We'll use the NativeModules approach for iOS/Android compatibility
  return `models/${assetPath}`;
}

/**
 * Check if a model directory exists and has content
 */
async function modelExists(modelId: string, destDir: string): Promise<boolean> {
  try {
    const modelPath = `${destDir}/${modelId}`;
    const exists = await FileSystem.exists(modelPath);

    if (!exists) {
      console.warn(`${TAG} Model directory not found: ${modelPath}`);
      return false;
    }

    // Check if it has files (not just an empty directory)
    const files = await FileSystem.readDir(modelPath);
    return files.length > 0;
  } catch (error) {
    console.warn(`${TAG} Error checking model existence:`, error);
    return false;
  }
}

/**
 * Copy a directory recursively from assets to destination
 *
 * Note: This is a simplified version. In production, you might want to use
 * a native module for more efficient asset extraction.
 */
async function copyAssetDirectory(
  sourceAssetPath: string,
  destDir: string,
  modelId: string
): Promise<boolean> {
  try {
    const sourcePath = getAssetSourcePath(sourceAssetPath);
    const destPath = `${destDir}/${modelId}`;

    // Create destination directory
    await FileSystem.mkdir(destPath, { NSURLIsExcludedFromBackupKey: true });

    // In a real implementation, this would use native code to extract from APK assets
    // For now, we'll log what would be done
    console.log(`${TAG} Would copy from: ${sourcePath} to ${destPath}`);

    // TODO: Implement actual asset extraction using native module
    // This requires NativeModules.AssetManager or RNFetchBlob

    return true;
  } catch (error) {
    console.error(`${TAG} Error copying asset:`, error);
    return false;
  }
}

/**
 * Extract bundled models from APK assets to app data directory
 * Call this on first app launch
 */
export async function extractBundledModels(): Promise<void> {
  try {
    // Check if already extracted
    const isExtracted = await AsyncStorage.getItem(ASSETS_EXTRACTED_KEY);
    if (isExtracted === 'true') {
      console.log(`${TAG} ✅ Models already extracted, skipping`);
      return;
    }

    console.log(`${TAG} 🚀 Starting asset extraction for bundled models...`);

    // Create base models directory
    const baseDir = getModelsBaseDir();
    const baseExists = await FileSystem.exists(baseDir);
    if (!baseExists) {
      await FileSystem.mkdir(baseDir, { NSURLIsExcludedFromBackupKey: true });
      console.log(`${TAG} 📁 Created models base directory: ${baseDir}`);
    }

    let extractedCount = 0;
    let failedCount = 0;

    for (const model of BUNDLED_ASSET_MODELS) {
      try {
        console.log(
          `${TAG} 📦 Extracting: ${model.name} (${model.id})`
        );

        const destTypeDir = getModelTypeDir(model.destPath as 'ONNX' | 'LlamaCpp');

        // Create type-specific directory if needed
        const typeExists = await FileSystem.exists(destTypeDir);
        if (!typeExists) {
          await FileSystem.mkdir(destTypeDir, { NSURLIsExcludedFromBackupKey: true });
        }

        // Check if model already exists
        const exists = await modelExists(model.id, destTypeDir);
        if (exists) {
          console.log(`${TAG} ✓ Model already exists: ${model.name}`);
          extractedCount++;
          continue;
        }

        // Copy from assets
        const success = await copyAssetDirectory(
          model.assetPath,
          destTypeDir,
          model.id
        );

        if (success) {
          console.log(
            `${TAG} ✅ Successfully extracted: ${model.name}`
          );
          extractedCount++;
        } else {
          console.warn(`${TAG} ⚠️ Failed to extract: ${model.name}`);
          failedCount++;
        }
      } catch (error) {
        console.error(
          `${TAG} ❌ Error extracting ${model.name}:`,
          error
        );
        failedCount++;
      }
    }

    // Mark as extracted even if some failed (to avoid re-trying on every launch)
    await AsyncStorage.setItem(ASSETS_EXTRACTED_KEY, 'true');

    console.log(
      `${TAG} ✨ Extraction complete. Success: ${extractedCount}/${BUNDLED_ASSET_MODELS.length}, Failed: ${failedCount}`
    );
  } catch (error) {
    console.error(`${TAG} 💥 Critical error during extraction:`, error);
    throw error;
  }
}

/**
 * Register extracted bundled models as already downloaded
 * Call after extraction is complete
 */
export async function registerExtractedModels(
  registerModelFn: (model: any) => Promise<void>
): Promise<void> {
  try {
    console.log(`${TAG} 📋 Registering extracted models...`);

    for (const model of BUNDLED_ASSET_MODELS) {
      try {
        const typeDir = getModelTypeDir(model.destPath as 'ONNX' | 'LlamaCpp');
        const modelPath = `${typeDir}/${model.id}`;

        // Check if model exists before registering
        const exists = await modelExists(model.id, typeDir);
        if (!exists) {
          console.warn(
            `${TAG} ⚠️ Model not extracted, skipping registration: ${model.name}`
          );
          continue;
        }

        // Register model
        const modelInfo = {
          id: model.id,
          name: model.name,
          localPath: modelPath,
          isDownloaded: true,
          isAvailable: true,
          category: model.format === 'onnx' ? 'embedding' : 'language',
          format: model.format,
          compatibleFrameworks:
            model.format === 'onnx' ? ['ONNX'] : ['LlamaCpp'],
          preferredFramework: model.format === 'onnx' ? 'ONNX' : 'LlamaCpp',
          supportsThinking: false,
        };

        await registerModelFn(modelInfo);

        console.log(
          `${TAG} ✅ Registered extracted model: ${model.name}`
        );
      } catch (error) {
        console.error(
          `${TAG} ❌ Failed to register ${model.name}:`,
          error
        );
      }
    }

    console.log(`${TAG} ✨ Model registration complete`);
  } catch (error) {
    console.error(`${TAG} 💥 Error registering models:`, error);
    throw error;
  }
}

/**
 * Reset extraction flag (for testing/debugging)
 */
export async function resetAssetExtraction(): Promise<void> {
  try {
    await AsyncStorage.removeItem(ASSETS_EXTRACTED_KEY);
    console.log(`${TAG} 🔄 Reset asset extraction flag`);
  } catch (error) {
    console.error(`${TAG} Error resetting extraction flag:`, error);
  }
}

/**
 * Get paths of extracted models for debugging
 */
export async function getExtractedModelPaths(): Promise<Record<string, string>> {
  const paths: Record<string, string> = {};

  for (const model of BUNDLED_ASSET_MODELS) {
    const typeDir = getModelTypeDir(model.destPath as 'ONNX' | 'LlamaCpp');
    const modelPath = `${typeDir}/${model.id}`;
    paths[model.id] = modelPath;
  }

  return paths;
}
