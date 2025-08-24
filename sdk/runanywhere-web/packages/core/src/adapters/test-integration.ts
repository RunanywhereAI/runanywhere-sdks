/**
 * Test file for adapter integration with pipeline
 * This demonstrates how adapters work with the adaptive pipeline manager
 */

import { ServiceRegistry } from '../registry/service-registry';
import { AdaptivePipelineManager } from '../pipeline/adaptive-pipeline-manager';
import { AdapterType } from '../interfaces';
import { SileroVADAdapter } from './vad/silero-vad.adapter';
import { WhisperSTTAdapter } from './stt/whisper-stt.adapter';
import { OpenAILLMAdapter } from './llm/openai-llm.adapter';
import { WebSpeechTTSAdapter } from './tts/webspeech-tts.adapter';

export async function testAdapterIntegration() {
  console.log('Starting adapter integration test...');

  // 1. Register adapters with the service registry
  const registry = ServiceRegistry.getInstance();

  registry.register(AdapterType.VAD, 'silero', SileroVADAdapter as any);
  registry.register(AdapterType.STT, 'whisper', WhisperSTTAdapter as any);
  registry.register(AdapterType.LLM, 'openai', OpenAILLMAdapter as any);
  registry.register(AdapterType.TTS, 'webspeech', WebSpeechTTSAdapter as any);

  console.log('Adapters registered successfully');

  // 2. List available adapters
  console.log('\nAvailable VAD adapters:', registry.getAvailable(AdapterType.VAD));
  console.log('Available STT adapters:', registry.getAvailable(AdapterType.STT));
  console.log('Available LLM adapters:', registry.getAvailable(AdapterType.LLM));
  console.log('Available TTS adapters:', registry.getAvailable(AdapterType.TTS));

  // 3. Create and configure pipeline

  const config = {
    vad: {
      adapter: 'silero',
      config: {
        positiveSpeechThreshold: 0.9,
        negativeSpeechThreshold: 0.75,
      }
    },
    stt: {
      adapter: 'whisper',
      config: {
        model: 'whisper-tiny',
      },
      model: 'whisper-tiny'
    },
    llm: {
      adapter: 'openai',
      config: {
        apiKey: process.env.OPENAI_API_KEY || 'test-key',
        defaultModel: 'gpt-3.5-turbo',
        systemPrompt: 'You are a helpful assistant.',
      }
    },
    tts: {
      adapter: 'webspeech',
      config: {
        rate: 1.0,
        pitch: 1.0,
        volume: 1.0,
      }
    }
  };

  const pipeline = new AdaptivePipelineManager(config);

  // Initialize pipeline with adapters
  const result = await pipeline.initialize();

  if (result.success) {
    console.log('\n✅ Pipeline initialized successfully with all adapters');

    // Test pipeline events
    pipeline.on('speech_start', () => {
      console.log('Speech detected by VAD adapter');
    });

    pipeline.on('transcription', (result) => {
      console.log('Transcription complete:', result.text);
    });

    pipeline.on('llm_response', (response) => {
      console.log('LLM response:', response.text);
    });

    pipeline.on('playback_end', () => {
      console.log('TTS playback complete');
    });

    pipeline.on('error', (error) => {
      console.error('Pipeline error:', error);
    });

    // Test adapter switching (fallback)
    console.log('\n🔄 Testing adapter fallback mechanism...');

    // Add a fallback STT adapter
    const fallbackConfig = {
      ...config,
      stt: [
        { adapter: 'whisper', priority: 1, model: 'whisper-tiny' },
        { adapter: 'whisper', priority: 2, model: 'whisper-base' }
      ]
    };

    // Re-initialize with fallback config
    const fallbackPipeline = new AdaptivePipelineManager(fallbackConfig);
    await fallbackPipeline.initialize();
    console.log('Fallback adapters configured');

    // Get pipeline state
    const state = pipeline.getState();
    console.log('\n📊 Pipeline State:', state);

    // Clean up
    pipeline.destroy();
    console.log('\n🧹 Pipeline destroyed successfully');

  } else {
    console.error('❌ Failed to initialize pipeline:', result.error);
  }

  console.log('\n✨ Integration test complete!');
}

// Example: Using adapters directly without pipeline
export async function testDirectAdapterUsage() {
  console.log('\n=== Testing Direct Adapter Usage ===\n');

  // Create and use VAD adapter directly
  const vadAdapter = new SileroVADAdapter();
  const vadResult = await vadAdapter.initialize();

  if (vadResult.success) {
    console.log('✅ VAD adapter initialized');

    vadAdapter.on('speech_start', () => {
      console.log('Direct VAD: Speech started');
    });

    vadAdapter.on('speech_end', (audio) => {
      console.log('Direct VAD: Speech ended, audio length:', audio.length);
    });

    // Start VAD
    await vadAdapter.start();
    console.log('VAD started, listening for speech...');

    // Check health
    console.log('VAD healthy:', vadAdapter.isHealthy());
    console.log('VAD metrics:', vadAdapter.getMetrics());

    // Clean up
    vadAdapter.destroy();
  }

  // Create and use TTS adapter directly
  const ttsAdapter = new WebSpeechTTSAdapter();
  const ttsResult = await ttsAdapter.initialize();

  if (ttsResult.success) {
    console.log('✅ TTS adapter initialized');
    console.log('Available voices:', ttsAdapter.supportedVoices.length);

    // Synthesize and play text
    const playResult = await ttsAdapter.synthesizeAndPlay(
      'Hello! This is a test of the Web Speech TTS adapter.',
      { rate: 1.2, pitch: 1.0 }
    );

    if (playResult.success) {
      console.log('✅ TTS synthesis and playback complete');
    }

    console.log('TTS metrics:', ttsAdapter.getMetrics());

    // Clean up
    ttsAdapter.destroy();
  }
}

// Run tests if this file is executed directly
if (require.main === module) {
  (async () => {
    await testAdapterIntegration();
    await testDirectAdapterUsage();
  })();
}
