// Main TTS Service
export { TTSService } from './services/tts-service';

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
