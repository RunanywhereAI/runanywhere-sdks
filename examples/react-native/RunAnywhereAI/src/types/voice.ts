/**
 * Voice Types - STT, TTS, and Voice Assistant
 *
 * Reference: examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Voice/
 */

/**
 * STT mode
 */
export enum STTMode {
  Batch = 'batch',
  Live = 'live',
}

/**
 * Voice pipeline status
 */
export enum VoicePipelineStatus {
  Idle = 'idle',
  Listening = 'listening',
  Processing = 'processing',
  Thinking = 'thinking',
  Speaking = 'speaking',
  Error = 'error',
}

/**
 * STT segment with timing
 */
export interface STTSegment {
  /** Transcribed text */
  text: string;

  /** Start time in seconds */
  startTime: number;

  /** End time in seconds */
  endTime: number;

  /** Speaker ID if diarization enabled */
  speakerId?: string;

  /** Confidence score */
  confidence: number;
}

/**
 * STT result
 */
export interface STTResult {
  /** Full transcription text */
  text: string;

  /** Segments with timing */
  segments: STTSegment[];

  /** Detected language */
  language?: string;

  /** Overall confidence */
  confidence: number;

  /** Audio duration in seconds */
  duration: number;

  /** Processing time in milliseconds */
  processingTime: number;
}

/**
 * TTS configuration
 */
export interface TTSConfiguration {
  /** Voice ID */
  voice: string;

  /** Speech rate (0.5 - 2.0) */
  rate: number;

  /** Pitch (0.5 - 2.0) */
  pitch: number;

  /** Volume (0.0 - 1.0) */
  volume: number;
}

/**
 * TTS result
 */
export interface TTSResult {
  /** Audio data (base64 encoded) */
  audioData: string;

  /** Audio duration in seconds */
  duration: number;

  /** Sample rate */
  sampleRate: number;

  /** Generation time in milliseconds */
  generationTime: number;
}

/**
 * Available voice
 */
export interface Voice {
  /** Voice ID */
  id: string;

  /** Display name */
  name: string;

  /** Language code */
  language: string;

  /** Voice gender */
  gender: 'male' | 'female' | 'neutral';

  /** Sample audio URL */
  sampleURL?: string;
}

/**
 * Recording state
 */
export interface RecordingState {
  /** Whether currently recording */
  isRecording: boolean;

  /** Recording duration in seconds */
  duration: number;

  /** Audio level (0-1) */
  audioLevel: number;

  /** Whether speech is detected */
  isSpeechDetected: boolean;
}

/**
 * Voice assistant conversation entry
 */
export interface VoiceConversationEntry {
  /** Unique ID */
  id: string;

  /** Speaker (user or assistant) */
  speaker: 'user' | 'assistant';

  /** Transcript text */
  text: string;

  /** Audio data if available */
  audioData?: string;

  /** Timestamp */
  timestamp: Date;

  /** Duration in seconds */
  duration?: number;
}

/**
 * Voice assistant state
 */
export interface VoiceAssistantState {
  /** Pipeline status */
  status: VoicePipelineStatus;

  /** Current user transcript (live) */
  currentTranscript: string;

  /** Conversation history */
  conversation: VoiceConversationEntry[];

  /** Recording state */
  recording: RecordingState;

  /** Is processing */
  isProcessing: boolean;

  /** Error message */
  error?: string;
}

/**
 * Audio settings
 */
export interface AudioSettings {
  /** Sample rate */
  sampleRate: number;

  /** Number of channels */
  channels: number;

  /** Bits per sample */
  bitsPerSample: number;

  /** Enable noise suppression */
  noiseSuppression: boolean;

  /** Enable echo cancellation */
  echoCancellation: boolean;
}

/**
 * VAD (Voice Activity Detection) settings
 */
export interface VADSettings {
  /** Energy threshold */
  energyThreshold: number;

  /** Silence duration to trigger end of speech (ms) */
  silenceDuration: number;

  /** Minimum speech duration (ms) */
  minSpeechDuration: number;

  /** Enable auto calibration */
  autoCalibration: boolean;
}
