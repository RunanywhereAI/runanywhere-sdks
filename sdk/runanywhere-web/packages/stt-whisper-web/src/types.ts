export interface WorkerMessage {
  audio: Float32Array;
  model: string;
  dtype: string;
  gpu: boolean;
  subtask: string;
  language: string | null;
}

export interface WorkerResponse {
  status: 'worker_ready' | 'progress' | 'update' | 'chunk-start' | 'chunk' | 'chunk-end' | 'complete' | 'error';
  data?: any;
  message?: string;
  progress?: number;
}

export interface TranscriptionChunk {
  text: string;
  timestamp: [number, number | null];
}

export interface TranscriptionOutput {
  text: string;
  chunks: TranscriptionChunk[];
}
