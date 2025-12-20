/**
 * RunAnywhere React Native SDK - Features
 *
 * Modular capabilities following the Swift SDK architecture.
 * Each capability provides a specific AI feature.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/
 */

// Base Component (abstract class and protocols)
export {
  BaseComponent,
  AnyServiceWrapper,
  type Component,
  type ServiceComponent,
  type ComponentInput,
  type ComponentOutput,
  type ComponentConfiguration,
  type ServiceWrapper,
} from '../Core/Components/BaseComponent';

// Speech-to-Text
export * from './STT';

// Text-to-Speech
export * from './TTS';

// Language Models (LLM)
export * from './LLM';

// Voice Activity Detection (VAD)
export * from './VAD';

// Speaker Diarization
export * from './SpeakerDiarization';

// Voice Agent (orchestrates VAD, STT, LLM, TTS)
export * from './VoiceAgent';
