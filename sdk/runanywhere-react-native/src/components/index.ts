/**
 * RunAnywhere React Native SDK - Components
 *
 * Modular components following the Swift SDK architecture.
 * Each component provides a specific AI capability.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/
 */

// Base Component (abstract class and protocols)
export {
  BaseComponent,
  type Component,
  type ServiceComponent,
  type ComponentInput,
  type ComponentOutput,
  type ComponentConfiguration,
  type ComponentInitParameters,
  type ServiceWrapper,
} from './BaseComponent';

// Speech-to-Text
export * from './STT';

// Text-to-Speech
export * from './TTS';

// Language Models (LLM)
export * from './LLM';

// Voice Activity Detection (VAD)
export * from './VAD';

// Wake Word Detection
export * from './WakeWord';

// Speaker Diarization
export * from './SpeakerDiarization';

// Vision Language Model (VLM)
export * from './VLM';

// Voice Agent (orchestrates VAD, STT, LLM, TTS)
export * from './VoiceAgent';
