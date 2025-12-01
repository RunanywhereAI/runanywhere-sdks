/**
 * STTTranscriptionResult.ts
 * Placeholder - needs full implementation matching iOS
 */

export interface STTTranscriptionResult {
  transcript: string;
  confidence: number;
  segments?: Array<{
    text: string;
    start: number;
    end: number;
  }>;
  language?: string;
  // Add all other properties from iOS STTTranscriptionResult
}

