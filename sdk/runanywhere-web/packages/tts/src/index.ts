// Main TTS Service
export { TTSService } from './services/tts-service';

// TTS Adapter
export { TTSAdapter, type TTSAdapterConfig } from './adapters/tts-adapter';

// Types
export type {
  TTSConfig,
  TTSOptions,
  SynthesisResult,
  SynthesisChunk,
  VoiceInfo,
  SynthesisProgress,
  StreamingOptions,
  TTSEvents
} from './types';

// Service token for DI
export const TTS_SERVICE_TOKEN = Symbol('tts-service');
