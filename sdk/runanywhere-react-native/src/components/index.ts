/**
 * RunAnywhere React Native SDK - Components
 *
 * Modular components following the Swift SDK architecture.
 * Each component provides a specific AI capability.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/
 */

// Speech-to-Text
export {
  STTComponent,
  createSTTComponent,
  type STTConfiguration,
  type STTInput,
  type STTOutput,
  type STTStreamHandle,
  type WordTimestamp,
  type TranscriptionAlternative,
  type TranscriptionMetadata,
  STTMode,
  DEFAULT_STT_CONFIG,
} from './STT';

// Text-to-Speech
export {
  TTSComponent,
  createTTSComponent,
  type TTSComponentConfiguration,
  type TTSInput,
  type TTSOutput,
  type TTSOptions,
  type PhonemeTimestamp,
  type SynthesisMetadata,
  type VoiceInfo,
  DEFAULT_TTS_CONFIG,
} from './TTS';

// Future components (to be implemented):
// - VADComponent (Voice Activity Detection)
// - LLMComponent (Large Language Models)
// - VLMComponent (Vision Language Models)
// - SpeakerDiarizationComponent
// - WakeWordComponent
// - VoiceAgentComponent
