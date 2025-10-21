export interface WhisperConfig {
  model: 'whisper-tiny' | 'whisper-base' | 'whisper-small';
  language?: string;
  task?: 'transcribe' | 'translate';
  temperature?: number;
  beamSize?: number;
  patience?: number;
  lengthPenalty?: number;
  repetitionPenalty?: number;
  noRepeatNgramSize?: number;
  returnTimestamps?: boolean;
  chunkLengthSec?: number;
  strideLengthSec?: number;
}

export interface TranscriptionSegment {
  text: string;
  start: number;
  end: number;
  confidence?: number;
  language?: string;
}

export interface TranscriptionResult {
  text: string;
  segments: TranscriptionSegment[];
  language?: string;
  duration: number;
  processingTime: number;
}

export interface DownloadProgress {
  loaded: number;
  total: number;
  progress: number;
}

export interface PartialTranscription {
  text: string;
  timestamp?: number;
}
