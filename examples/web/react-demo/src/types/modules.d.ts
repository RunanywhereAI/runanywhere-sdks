declare module '@runanywhere/react' {
  export interface VoicePipelineState {
    isInitialized: boolean;
    isListening: boolean;
    isProcessing: boolean;
    error: Error | null;
    transcription: string;
    llmResponse: string;
    isPlaying: boolean;
  }

  export interface VoicePipelineActions {
    initialize: () => Promise<void>;
    start: () => Promise<void>;
    stop: () => Promise<void>;
    pause: () => Promise<void>;
    resume: () => Promise<void>;
    destroy: () => void;
  }

  export interface UseVoicePipelineOptions {
    enableTranscription?: boolean;
    enableLLM?: boolean;
    enableTTS?: boolean;
    autoPlayTTS?: boolean;
    whisperConfig?: {
      model?: 'whisper-tiny' | 'whisper-base' | 'whisper-small';
    };
    llmConfig?: {
      apiKey?: string;
      baseUrl?: string;
      model?: string;
      temperature?: number;
      maxTokens?: number;
      systemPrompt?: string;
    };
    ttsConfig?: {
      voice?: string;
      rate?: number;
      pitch?: number;
      volume?: number;
    };
  }

  export function useVoicePipeline(
    options?: UseVoicePipelineOptions
  ): [VoicePipelineState, VoicePipelineActions];
}
