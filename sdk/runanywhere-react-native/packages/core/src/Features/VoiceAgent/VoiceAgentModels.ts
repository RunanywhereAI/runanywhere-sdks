/**
 * VoiceAgentModels.ts
 *
 * Input/Output models for Voice Agent capability.
 * VoiceAgent is a composite capability that orchestrates LLM, STT, TTS, and VAD.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/VoiceAgent/VoiceAgentCapability.swift
 */

// ============================================================================
// Voice Agent Result
// ============================================================================

/**
 * Result from voice agent processing.
 * Contains outputs from each stage of the pipeline.
 */
export interface VoiceAgentResult {
  /** Whether speech was detected by VAD */
  speechDetected: boolean;
  /** Transcription from STT (null if no speech or STT failed) */
  transcription: string | null;
  /** Response from LLM (null if no transcription or LLM failed) */
  response: string | null;
  /** Synthesized audio from TTS (null if no response or TTS failed) */
  synthesizedAudio: Buffer | Uint8Array | null;
}

// ============================================================================
// Voice Agent Event (streaming)
// ============================================================================

/**
 * Events emitted during voice agent streaming processing.
 * These are the intermediate results from the pipeline.
 */
export type VoiceAgentStreamEvent =
  | { type: 'processed'; result: VoiceAgentResult }
  | { type: 'vadTriggered'; isSpeech: boolean }
  | { type: 'transcriptionAvailable'; text: string }
  | { type: 'responseGenerated'; text: string }
  | { type: 'audioSynthesized'; data: Buffer | Uint8Array }
  | { type: 'error'; error: Error };

/**
 * Legacy enum for backwards compatibility.
 * @deprecated Use VoiceAgentStreamEvent type instead.
 */
export enum VoiceAgentEvent {
  Processed = 'processed',
  VADTriggered = 'vadTriggered',
  TranscriptionAvailable = 'transcriptionAvailable',
  ResponseGenerated = 'responseGenerated',
  AudioSynthesized = 'audioSynthesized',
  Error = 'error',
}

// ============================================================================
// Component Load State
// ============================================================================

/**
 * Load state for individual components within VoiceAgent.
 * Matches iOS ComponentLoadState enum.
 */
export type ComponentLoadState =
  | { type: 'notLoaded' }
  | { type: 'loading' }
  | { type: 'loaded'; modelId: string }
  | { type: 'error'; message: string };

/**
 * Create a notLoaded state
 */
export function notLoadedState(): ComponentLoadState {
  return { type: 'notLoaded' };
}

/**
 * Create a loading state
 */
export function loadingComponentState(): ComponentLoadState {
  return { type: 'loading' };
}

/**
 * Create a loaded state
 */
export function loadedComponentState(modelId: string): ComponentLoadState {
  return { type: 'loaded', modelId };
}

/**
 * Create an error state
 */
export function errorComponentState(message: string): ComponentLoadState {
  return { type: 'error', message };
}

// ============================================================================
// Voice Agent Component States
// ============================================================================

/**
 * Aggregate state of all components within VoiceAgent.
 * Useful for UI binding and status display.
 * Matches iOS VoiceAgentComponentStates struct.
 */
export interface VoiceAgentComponentStates {
  /** STT component load state */
  readonly stt: ComponentLoadState;
  /** LLM component load state */
  readonly llm: ComponentLoadState;
  /** TTS component load state */
  readonly tts: ComponentLoadState;
  /** VAD initialization state (true = ready, false = not ready) */
  readonly vadReady: boolean;
}

/**
 * Check if all components are fully ready
 */
export function isVoiceAgentFullyReady(
  states: VoiceAgentComponentStates
): boolean {
  return (
    states.stt.type === 'loaded' &&
    states.llm.type === 'loaded' &&
    states.tts.type === 'loaded' &&
    states.vadReady
  );
}

/**
 * Get list of missing/unloaded components
 */
export function getMissingComponents(
  states: VoiceAgentComponentStates
): string[] {
  const missing: string[] = [];
  if (states.stt.type !== 'loaded') missing.push('STT');
  if (states.llm.type !== 'loaded') missing.push('LLM');
  if (states.tts.type !== 'loaded') missing.push('TTS');
  if (!states.vadReady) missing.push('VAD');
  return missing;
}

// ============================================================================
// Voice Agent Error
// ============================================================================

/**
 * Errors specific to VoiceAgent operations.
 * Matches iOS VoiceAgentError enum.
 */
export class VoiceAgentError extends Error {
  constructor(
    message: string,
    public readonly code: VoiceAgentErrorCode
  ) {
    super(message);
    this.name = 'VoiceAgentError';
  }

  /**
   * No transcription was produced from the audio
   */
  static emptyTranscription(): VoiceAgentError {
    return new VoiceAgentError(
      'Transcription was empty - no speech detected or transcription failed',
      VoiceAgentErrorCode.EmptyTranscription
    );
  }

  /**
   * Pipeline was interrupted (e.g., user cancelled, component failed mid-stream)
   */
  static pipelineInterrupted(reason: string): VoiceAgentError {
    return new VoiceAgentError(
      `Pipeline was interrupted: ${reason}`,
      VoiceAgentErrorCode.PipelineInterrupted
    );
  }

  /**
   * Component not initialized
   */
  static notInitialized(): VoiceAgentError {
    return new VoiceAgentError(
      'Voice Agent is not initialized. Call initialize() first.',
      VoiceAgentErrorCode.NotInitialized
    );
  }

  /**
   * Component failed to initialize
   */
  static componentFailed(
    component: string,
    underlying?: Error
  ): VoiceAgentError {
    const message = underlying
      ? `${component} component failed: ${underlying.message}`
      : `${component} component failed`;
    return new VoiceAgentError(message, VoiceAgentErrorCode.ComponentFailed);
  }
}

/**
 * Error codes for VoiceAgent errors
 */
export enum VoiceAgentErrorCode {
  EmptyTranscription = 'empty_transcription',
  PipelineInterrupted = 'pipeline_interrupted',
  NotInitialized = 'not_initialized',
  ComponentFailed = 'component_failed',
}
