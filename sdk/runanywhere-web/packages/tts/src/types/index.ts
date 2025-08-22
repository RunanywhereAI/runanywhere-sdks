export interface TTSConfig {
  engine?: 'web-speech' | 'onnx';
  voice?: string;
  rate?: number;
  pitch?: number;
  volume?: number;
  language?: string;
  modelUrl?: string;
  enableSSML?: boolean;
  timeout?: number;
}

export interface TTSOptions {
  voice?: string;
  rate?: number;
  pitch?: number;
  volume?: number;
  language?: string;
  enableSSML?: boolean;
}

export interface SynthesisResult {
  audioBuffer: AudioBuffer;
  duration: number;
  processingTime: number;
  voice: string;
  text: string;
}

export interface SynthesisChunk {
  audioData: Float32Array;
  sequence: number;
  isComplete: boolean;
  timestamp: number;
}

export interface VoiceInfo {
  name: string;
  language: string;
  gender?: 'male' | 'female' | 'neutral';
  quality?: 'low' | 'medium' | 'high';
  isDefault: boolean;
  isLocal: boolean;
}

export interface SynthesisProgress {
  text: string;
  progress: number;
  estimatedDuration?: number;
}

export interface StreamingOptions extends TTSOptions {
  chunkSize?: number;
  bufferSize?: number;
}

// Events
export interface TTSEvents {
  'ready': void;
  'loading': void;
  'error': Error;
  'synthesisStart': { text: string };
  'synthesisProgress': SynthesisProgress;
  'synthesisChunk': SynthesisChunk;
  'synthesisComplete': SynthesisResult;
  'playbackStart': void;
  'playbackEnd': void;
  'voicesChanged': VoiceInfo[];
}
