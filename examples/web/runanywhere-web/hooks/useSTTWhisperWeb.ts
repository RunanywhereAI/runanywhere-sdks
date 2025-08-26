import { useState, useCallback, useRef, useEffect } from 'react';
import { WhisperWebSTTAdapter, type WhisperWebSTTConfig } from '@runanywhere/stt-whisper-web';

export function useSTTWhisperWeb(config?: Partial<WhisperWebSTTConfig>) {
  const [state, setState] = useState({
    isInitialized: false,
    isTranscribing: false,
    error: null as string | null,
    lastTranscription: null as any,
    isWorkerReady: false,
    modelLoadingProgress: 0,
    modelLoadingMessage: ''
  });

  const adapterRef = useRef<WhisperWebSTTAdapter | null>(null);

  const initialize = useCallback(async () => {
    if (state.isInitialized || adapterRef.current) return;

    try {
      setState(prev => ({ ...prev, error: null }));

      const adapter = new WhisperWebSTTAdapter();

      // Set up event listeners
      adapter.on('model_loading', (progress) => {
        setState(prev => ({
          ...prev,
          modelLoadingProgress: progress.progress,
          modelLoadingMessage: progress.message || 'Loading model...'
        }));
      });

      adapter.on('partial_transcript', (text) => {
        setState(prev => ({
          ...prev,
          lastTranscription: { ...prev.lastTranscription, text }
        }));
      });

      adapter.on('error', (error) => {
        setState(prev => ({
          ...prev,
          error: error.message,
          isTranscribing: false
        }));
      });

      const result = await adapter.initialize({
        model: 'onnx-community/whisper-tiny',
        device: 'wasm',
        dtype: 'q8',
        ...config
      });

      if (result.success) {
        adapterRef.current = adapter;
        setState(prev => ({
          ...prev,
          isInitialized: true,
          isWorkerReady: true,
          modelLoadingProgress: 100,
          modelLoadingMessage: 'Ready'
        }));
      } else {
        setState(prev => ({
          ...prev,
          error: result.error.message
        }));
      }
    } catch (error) {
      setState(prev => ({
        ...prev,
        error: `Initialization failed: ${error}`
      }));
    }
  }, [config]); // FIXED: Removed state.isInitialized from dependencies

  const transcribe = useCallback(async (audio: Float32Array, options?: { language?: string; task?: 'transcribe' | 'translate' }) => {
    if (!adapterRef.current || !state.isWorkerReady) {
      setState(prev => ({ ...prev, error: 'Adapter not ready' }));
      return null;
    }

    setState(prev => ({
      ...prev,
      isTranscribing: true,
      error: null,
      lastTranscription: null
    }));

    try {
      const result = await adapterRef.current.transcribe(audio, options);

      if (result.success) {
        setState(prev => ({
          ...prev,
          isTranscribing: false,
          lastTranscription: result.value
        }));
        return result.value;
      } else {
        setState(prev => ({
          ...prev,
          isTranscribing: false,
          error: result.error.message
        }));
      }
    } catch (error) {
      setState(prev => ({
        ...prev,
        isTranscribing: false,
        error: `Transcription failed: ${error}`
      }));
    }
    return null;
  }, [state.isWorkerReady]);

  const reset = useCallback(() => {
    setState(prev => ({
      ...prev,
      error: null,
      lastTranscription: null,
      isTranscribing: false
    }));
  }, []);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (adapterRef.current) {
        adapterRef.current.destroy();
        adapterRef.current = null;
      }
    };
  }, []);

  return {
    ...state,
    initialize,
    transcribe,
    reset,
    metrics: adapterRef.current?.getMetrics() || { totalTranscriptions: 0, avgProcessingTime: 0 }
  };
}
