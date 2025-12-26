/**
 * RunAnywhere Extensions
 *
 * Modular extensions for the RunAnywhere SDK, following the iOS pattern.
 * Each extension provides a specific capability domain.
 */

// Text Generation (LLM)
export * as TextGeneration from './RunAnywhere+TextGeneration';

// Speech-to-Text
export * as STT from './RunAnywhere+STT';

// Text-to-Speech
export * as TTS from './RunAnywhere+TTS';

// Voice Activity Detection
export * as VAD from './RunAnywhere+VAD';

// Voice Session & Voice Agent
export * as VoiceSession from './RunAnywhere+VoiceSession';

// Storage Management
export * as Storage from './RunAnywhere+Storage';

// Model Management
export * as Models from './RunAnywhere+Models';

// Structured Output
export * as StructuredOutput from './RunAnywhere+StructuredOutput';

// Logging
export * as Logging from './RunAnywhere+Logging';
