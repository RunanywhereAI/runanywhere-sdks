import { useEffect, useRef, useState, useCallback } from 'react';
import {
  AdaptivePipelineManager,
  type PipelineConfig,
  ServiceRegistry,
  AdapterType
} from '@runanywhere/core';

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

export interface UseVoicePipelineOptions extends Partial<PipelineConfig> {
  autoStart?: boolean;
  enableTranscription?: boolean;
  enableLLM?: boolean;
  enableTTS?: boolean;
  autoPlayTTS?: boolean;
  whisperConfig?: {
    model?: string;
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
  options: UseVoicePipelineOptions = {}
): [VoicePipelineState, VoicePipelineActions] {
  const pipelineRef = useRef<AdaptivePipelineManager | null>(null);
  const [isRegistered, setIsRegistered] = useState(false);

  const [state, setState] = useState<VoicePipelineState>({
    isInitialized: false,
    isListening: false,
    isProcessing: false,
    error: null,
    transcription: '',
    llmResponse: '',
    isPlaying: false
  });

  console.log('useVoicePipeline: Current state:', state, 'Options:', options);

  const initialize = useCallback(async () => {
    try {
      if (pipelineRef.current) {
        return;
      }

      console.log('useVoicePipeline: Starting initialization', options);

      // Ensure adapters are registered
      const registry = ServiceRegistry.getInstance();

      // Check if adapters are available, if not, try to register them
      if (!isRegistered) {
        console.log('useVoicePipeline: Registering adapters...');
        // These imports will auto-register the adapters
        await import('@runanywhere/vad-silero').catch((e) => console.warn('Failed to import vad-silero:', e));
        await import('@runanywhere/stt-whisper').catch((e) => console.warn('Failed to import stt-whisper:', e));
        await import('@runanywhere/llm-openai').catch((e) => console.warn('Failed to import llm-openai:', e));
        await import('@runanywhere/tts-webspeech').catch((e) => console.warn('Failed to import tts-webspeech:', e));
        setIsRegistered(true);
      }

      // Build pipeline configuration
      const pipelineConfig: PipelineConfig = {
        vad: { adapter: 'silero' },
        stt: options.enableTranscription !== false ? {
          adapter: 'whisper',
          model: options.whisperConfig?.model || 'whisper-base'
        } : undefined,
        llm: options.enableLLM !== false && options.llmConfig?.apiKey ? {
          adapter: 'openai',
          config: options.llmConfig
        } : undefined,
        tts: options.enableTTS !== false ? {
          adapter: 'webspeech',
          config: options.ttsConfig
        } : undefined
      };

      // Initialize pipeline
      pipelineRef.current = new AdaptivePipelineManager(pipelineConfig);

      // Set up event listeners
      const pipeline = pipelineRef.current;

      pipeline.on('state_change', (pipelineState: any) => {
        setState(prev => ({
          ...prev,
          isListening: pipelineState.isRunning,
          isProcessing: pipelineState.isProcessing
        }));
      });

      pipeline.on('error', (error: Error) => {
        setState(prev => ({ ...prev, error, isProcessing: false }));
      });

      pipeline.on('speech_start', () => {
        setState(prev => ({ ...prev, isProcessing: true }));
      });

      pipeline.on('transcription', (result: any) => {
        setState(prev => ({
          ...prev,
          transcription: result.text || result,
          isProcessing: false
        }));
      });

      pipeline.on('llm_response', (result: any) => {
        setState(prev => ({ ...prev, llmResponse: result.text || result }));
      });

      pipeline.on('playback_start', () => {
        setState(prev => ({ ...prev, isPlaying: true }));
      });

      pipeline.on('playback_end', () => {
        setState(prev => ({ ...prev, isPlaying: false }));
      });

      // Initialize the pipeline
      const result = await pipeline.initialize();
      if (!result.success) {
        throw result.error;
      }

      setState(prev => ({ ...prev, isInitialized: true, error: null }));

      // Auto-start if configured
      if (options.autoStart) {
        await pipeline.start();
      }

    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      setState(prev => ({ ...prev, error: err }));
    }
  }, [options, isRegistered]);

  const start = useCallback(async () => {
    if (!pipelineRef.current) {
      throw new Error('Pipeline not initialized');
    }
    await pipelineRef.current.start();
  }, []);

  const stop = useCallback(async () => {
    if (!pipelineRef.current) {
      return;
    }
    await pipelineRef.current.stop();
  }, []);

  const pause = useCallback(async () => {
    if (!pipelineRef.current) {
      return;
    }
    await pipelineRef.current.pause();
  }, []);

  const resume = useCallback(async () => {
    if (!pipelineRef.current) {
      return;
    }
    await pipelineRef.current.resume();
  }, []);

  const destroy = useCallback(() => {
    if (pipelineRef.current) {
      pipelineRef.current.destroy();
      pipelineRef.current = null;
    }
    setState({
      isInitialized: false,
      isListening: false,
      isProcessing: false,
      error: null,
      transcription: '',
      llmResponse: '',
      isPlaying: false
    });
  }, []);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      destroy();
    };
  }, [destroy]);

  const actions: VoicePipelineActions = {
    initialize,
    start,
    stop,
    pause,
    resume,
    destroy
  };

  return [state, actions];
}
