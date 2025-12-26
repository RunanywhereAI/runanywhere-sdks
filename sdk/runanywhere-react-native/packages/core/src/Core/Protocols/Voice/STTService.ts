/**
 * STTService.ts
 *
 * Protocol for STT service implementations
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/STT/STTComponent.swift
 */

import type { STTTranscriptionResult } from '../../Models/STT/STTTranscriptionResult';

/**
 * Protocol for STT service implementations
 *
 * All STT services must implement this protocol to work with STTComponent
 */
export interface STTService {
  /**
   * Initialize the STT service with model path
   *
   * @param modelPath - Optional path to model file
   * @throws Error if initialization fails
   */
  initialize(modelPath?: string | null): Promise<void>;

  /**
   * Transcribe audio data
   *
   * @param audioData - Audio data (base64 encoded or ArrayBuffer)
   * @param options - STT options (sample rate, language, etc.)
   * @returns Promise resolving to transcription result
   * @throws Error if transcription fails
   */
  transcribe(
    audioData: string | ArrayBuffer,
    options?: {
      sampleRate?: number;
      language?: string;
      enablePunctuation?: boolean;
    }
  ): Promise<STTTranscriptionResult>;

  /**
   * Stream transcribe audio data
   *
   * @param audioStream - Async iterable of audio chunks
   * @param options - STT options
   * @param onPartial - Callback for partial results
   * @returns Promise resolving to final transcription result
   * @throws Error if transcription fails
   */
  streamTranscribe?(
    audioStream: AsyncIterable<string | ArrayBuffer>,
    options?: {
      sampleRate?: number;
      language?: string;
    },
    onPartial?: (text: string, confidence: number) => void
  ): Promise<STTTranscriptionResult>;

  /**
   * Check if service is ready
   */
  readonly isReady: boolean;

  /**
   * Whether this service supports streaming transcription
   * Matches iOS: public var supportsStreaming: Bool
   */
  readonly supportsStreaming?: boolean;

  /**
   * Current model identifier
   */
  readonly currentModel: string | null;

  /**
   * Clean up and release resources
   */
  cleanup(): Promise<void>;
}
