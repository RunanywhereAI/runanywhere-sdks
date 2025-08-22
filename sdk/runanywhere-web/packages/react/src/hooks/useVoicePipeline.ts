import { useEffect, useRef, useState, useCallback } from 'react';
import { DIContainer } from '@runanywhere/core';
import { EnhancedVoicePipelineManager, EnhancedPipelineConfig } from '@runanywhere/voice';

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

export interface UseVoicePipelineOptions extends EnhancedPipelineConfig {
  autoStart?: boolean;
}

export function useVoicePipeline(
  options: UseVoicePipelineOptions = {}
): [VoicePipelineState, VoicePipelineActions] {
  const pipelineRef = useRef<EnhancedVoicePipelineManager | null>(null);
  const containerRef = useRef<DIContainer | null>(null);

  const [state, setState] = useState<VoicePipelineState>({
    isInitialized: false,
    isListening: false,
    isProcessing: false,
    error: null,
    transcription: '',
    llmResponse: '',
    isPlaying: false
  });

  const initialize = useCallback(async () => {
    try {
      if (pipelineRef.current) {
        return;
      }

      // Create DI container
      containerRef.current = new DIContainer();

      // Initialize pipeline
      pipelineRef.current = new EnhancedVoicePipelineManager(
        containerRef.current,
        options
      );

      // Set up event listeners
      const pipeline = pipelineRef.current;

      pipeline.on('started', () => {
        setState(prev => ({ ...prev, isListening: true }));
      });

      pipeline.on('stopped', () => {
        setState(prev => ({ ...prev, isListening: false, isProcessing: false }));
      });

      pipeline.on('error', (error: Error) => {
        setState(prev => ({ ...prev, error, isProcessing: false }));
      });

      pipeline.on('vadSpeechStart', () => {
        setState(prev => ({ ...prev, isProcessing: true }));
      });

      pipeline.on('transcription', (result: any) => {
        setState(prev => ({
          ...prev,
          transcription: result.text,
          isProcessing: false
        }));
      });

      pipeline.on('llmResponse', (result: any) => {
        setState(prev => ({ ...prev, llmResponse: result.text }));
      });

      pipeline.on('ttsPlaybackStart', () => {
        setState(prev => ({ ...prev, isPlaying: true }));
      });

      pipeline.on('ttsPlaybackEnd', () => {
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
  }, [options]);

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
    if (containerRef.current) {
      containerRef.current = null;
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
