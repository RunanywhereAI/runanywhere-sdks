/**
 * RunAnywhere Web SDK - TTS Types (ONNX Backend)
 *
 * Re-exports generic TTS types from core and defines backend-specific
 * voice configuration for sherpa-onnx Piper/VITS models.
 */

// Re-export generic TTS types from core
export type { TTSSynthesisResult, TTSSynthesizeOptions } from '@runanywhere/web';

// ---------------------------------------------------------------------------
// Backend-specific: sherpa-onnx voice configuration
// ---------------------------------------------------------------------------

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
