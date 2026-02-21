/** RunAnywhere Web SDK - TTS Types */

export interface TTSVoiceConfig {
  voiceId: string;
  /** Path to the VITS/Piper model ONNX file in sherpa FS */
  modelPath: string;
  /** Path to the tokens.txt file in sherpa FS */
  tokensPath: string;
  /** Path to the espeak-ng-data directory in sherpa FS (for Piper models) */
  dataDir?: string;
  /** Path to the lexicon file in sherpa FS (optional) */
  lexicon?: string;
  /** Number of threads (default: 1) */
  numThreads?: number;
}

export interface TTSSynthesisResult {
  /** Raw PCM audio data */
  audioData: Float32Array;
  /** Audio sample rate */
  sampleRate: number;
  /** Duration in milliseconds */
  durationMs: number;
  /** Processing time in milliseconds */
  processingTimeMs: number;
  [key: string]: unknown;
}

export interface TTSSynthesizeOptions {
  /** Speaker ID for multi-speaker models (default: 0) */
  speakerId?: number;
  /** Speed factor (default: 1.0, >1 = faster, <1 = slower) */
  speed?: number;
}
