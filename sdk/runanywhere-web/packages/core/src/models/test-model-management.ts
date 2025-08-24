/**
 * Test file for model management system integration
 */

import { ModelRegistry } from './model-registry';
import { ModelLoader } from './model-loader';
import { logger } from '../utils/logger';

export async function testModelManagement() {
  console.log('=== Testing Model Management System ===\n');

  // 1. Initialize the registry
  const registry = ModelRegistry.getInstance();
  const initResult = await registry.initialize();

  if (!initResult.success) {
    console.error('Failed to initialize registry:', initResult.error);
    return;
  }

  console.log('✅ Model registry initialized');

  // 2. List available models
  console.log('\n📋 Available Models:');
  const allModels = registry.getAvailableModels();
  for (const model of allModels) {
    console.log(`  - ${model.id}: ${model.name} (${model.type}, ${model.size} bytes)`);
  }

  // List STT models specifically
  console.log('\n🎤 STT Models:');
  const sttModels = registry.getAvailableModels('stt');
  for (const model of sttModels) {
    console.log(`  - ${model.id}: ${model.description}`);
    if (model.performance) {
      console.log(`    Latency: ${model.performance.latency}, Throughput: ${model.performance.throughput}`);
    }
  }

  // 3. Test model downloading with progress
  console.log('\n📥 Testing Model Download:');
  const loader = new ModelLoader();

  const modelId = 'whisper-tiny';
  console.log(`Downloading model: ${modelId}`);

  const downloadResult = await loader.loadModel(modelId, {
    onProgress: (progress) => {
      console.log(`  Progress: ${progress.progress}% - ${progress.message}`);
      if (progress.speed) {
        const speedMB = (progress.speed / (1024 * 1024)).toFixed(2);
        console.log(`  Speed: ${speedMB} MB/s`);
      }
      if (progress.estimatedTimeRemaining) {
        console.log(`  ETA: ${Math.round(progress.estimatedTimeRemaining)}s`);
      }
    }
  });

  if (downloadResult.success) {
    console.log(`✅ Model downloaded successfully (${downloadResult.value.byteLength} bytes)`);
  } else {
    console.error(`❌ Download failed: ${downloadResult.error.message}`);
  }

  // 4. Test cache functionality
  console.log('\n💾 Testing Cache:');

  // Check cached models
  const cachedModels = await registry.getCachedModels();
  console.log(`Cached models: ${cachedModels.join(', ') || 'none'}`);

  // Get cache size
  const cacheSize = await registry.getCacheSize();
  console.log(`Total cache size: ${(cacheSize / (1024 * 1024)).toFixed(2)} MB`);

  // Test loading from cache
  if (downloadResult.success) {
    console.log('\nTesting cache retrieval...');
    const startTime = Date.now();

    const cachedResult = await registry.downloadModel(modelId, {
      preferCache: true,
      onProgress: (progress, message) => {
        console.log(`  ${message}`);
      }
    });

    const loadTime = Date.now() - startTime;

    if (cachedResult.success) {
      console.log(`✅ Model loaded from cache in ${loadTime}ms`);
    }
  }

  // 5. Test concurrent downloads
  console.log('\n🔄 Testing Concurrent Downloads:');

  const models = ['whisper-base', 'speecht5-tts'];
  const downloadPromises = models.map(async (id) => {
    console.log(`Starting download: ${id}`);
    return loader.loadModel(id, {
      onProgress: (progress) => {
        if (progress.progress % 25 === 0) {
          console.log(`  ${progress.modelId}: ${progress.progress}%`);
        }
      }
    });
  });

  const results = await Promise.all(downloadPromises);

  for (let i = 0; i < models.length; i++) {
    const result = results[i];
    const modelId = models[i];
    if (result.success) {
      console.log(`✅ ${modelId} downloaded`);
    } else {
      console.log(`❌ ${modelId} failed: ${result.error.message}`);
    }
  }

  // 6. Test model loading with runtime
  console.log('\n🚀 Testing Model Loading with Runtime:');

  // Note: This would fail in practice without the actual runtime libraries
  // Just demonstrating the API
  const onnxResult = await registry.loadModel('whisper-tiny', 'onnx', {
    onProgress: (progress, message) => {
      console.log(`  ${message}`);
    }
  });

  if (onnxResult.success) {
    console.log('✅ Model loaded into ONNX runtime');
  } else {
    console.log(`⚠️ ONNX runtime not available: ${onnxResult.error.message}`);
  }

  // 7. Test queue management
  console.log('\n📊 Queue Status:');
  console.log(`Active downloads: ${loader.getActiveDownloads().join(', ') || 'none'}`);
  console.log(`Queued downloads: ${loader.getQueuedDownloads().join(', ') || 'none'}`);

  // 8. Cleanup options
  console.log('\n🧹 Cache Management:');
  console.log('Available operations:');
  console.log('  - registry.clearCache(modelId) - Clear specific model');
  console.log('  - registry.clearCache() - Clear all models');
  console.log('  - loader.cancelDownload(modelId) - Cancel specific download');
  console.log('  - loader.cancelAllDownloads() - Cancel all downloads');

  console.log('\n✨ Model Management Test Complete!');
}

// Example: Using with adapters
export async function testWithAdapters() {
  console.log('\n=== Testing Model Management with Adapters ===\n');

  const registry = ModelRegistry.getInstance();
  await registry.initialize();

  // Simulate adapter requesting a model
  class MockWhisperAdapter {
    private model?: any;

    async loadModel(modelId: string): Promise<void> {
      console.log(`Adapter: Loading model ${modelId}...`);

      // Download model data
      const result = await registry.downloadModel(modelId, {
        onProgress: (progress, message) => {
          if (progress % 20 === 0) {
            console.log(`  Adapter progress: ${progress}% - ${message}`);
          }
        }
      });

      if (!result.success) {
        throw result.error;
      }

      console.log(`Adapter: Model data received (${result.value.byteLength} bytes)`);

      // In real implementation, would initialize the actual model
      // For now, just store reference
      this.model = {
        id: modelId,
        data: result.value,
        loaded: true
      };

      console.log(`✅ Adapter: Model ${modelId} ready for inference`);
    }

    isModelLoaded(): boolean {
      return !!this.model?.loaded;
    }
  }

  // Test the adapter
  const adapter = new MockWhisperAdapter();
  await adapter.loadModel('whisper-tiny');

  console.log(`Model loaded in adapter: ${adapter.isModelLoaded()}`);

  // Show how cache helps on second load
  console.log('\n🔄 Testing second adapter instance (should use cache):');
  const adapter2 = new MockWhisperAdapter();
  const startTime = Date.now();
  await adapter2.loadModel('whisper-tiny');
  const loadTime = Date.now() - startTime;
  console.log(`Second load completed in ${loadTime}ms`);
}

// Run tests if executed directly
if (require.main === module) {
  (async () => {
    await testModelManagement();
    await testWithAdapters();
  })().catch(console.error);
}
