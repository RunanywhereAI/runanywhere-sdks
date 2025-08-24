/**
 * Adapter exports and auto-registration
 */

import { ServiceRegistry } from '../registry/service-registry';

// VAD Adapters
export { SileroVADAdapter, SileroVADAdapterMetadata } from './vad/silero-vad.adapter';

// STT Adapters
export { WhisperSTTAdapter, WhisperSTTAdapterMetadata } from './stt/whisper-stt.adapter';

// LLM Adapters
export { OpenAILLMAdapter, OpenAILLMAdapterMetadata } from './llm/openai-llm.adapter';

// TTS Adapters
export { WebSpeechTTSAdapter, WebSpeechTTSAdapterMetadata } from './tts/webspeech-tts.adapter';

// Import AdapterType enum
import { AdapterType } from '../interfaces';

// Auto-registration function for convenience
export function registerBuiltInAdapters(): void {
  const registry = ServiceRegistry.getInstance();

  // Import and register adapters dynamically
  // This allows tree-shaking if not used

  // Register VAD adapters
  import('./vad/silero-vad.adapter').then(({ SileroVADAdapter }) => {
    registry.register(AdapterType.VAD, 'silero', SileroVADAdapter as any);
  });

  // Register STT adapters
  import('./stt/whisper-stt.adapter').then(({ WhisperSTTAdapter }) => {
    registry.register(AdapterType.STT, 'whisper', WhisperSTTAdapter as any);
  });

  // Register LLM adapters
  import('./llm/openai-llm.adapter').then(({ OpenAILLMAdapter }) => {
    registry.register(AdapterType.LLM, 'openai', OpenAILLMAdapter as any);
  });

  // Register TTS adapters
  import('./tts/webspeech-tts.adapter').then(({ WebSpeechTTSAdapter }) => {
    registry.register(AdapterType.TTS, 'webspeech', WebSpeechTTSAdapter as any);
  });
}
