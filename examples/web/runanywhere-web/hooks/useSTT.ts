'use client';

import { useState, useCallback, useRef, useEffect } from 'react';
import { WhisperSTTAdapter, type WhisperSTTConfig } from '@runanywhere/stt-whisper';
import type { TranscriptionResult, ModelInfo } from '@runanywhere/core';

interface STTState {
  isInitialized: boolean;
  isModelLoaded: boolean;
  isTranscribing: boolean;
  error: string | null;
  lastTranscription: TranscriptionResult | null;
  modelLoadProgress: number;
  modelLoadMessage: string;
}

/**
 * Hook that uses the @runanywhere/stt-whisper package
 * This is an example of how to consume the STT SDK adapter in a React app
 */
export function useSTT(config?: Partial<WhisperSTTConfig>) {
  const [state, setState] = useState<STTState>({
    isInitialized: false,
    isModelLoaded: false,
    isTranscribing: false,
    error: null,
    lastTranscription: null,
    modelLoadProgress: 0,
    modelLoadMessage: '',
  });

  const adapterRef = useRef<WhisperSTTAdapter | null>(null);

  // Initialize STT
  const initialize = useCallback(async () => {
    if (state.isInitialized) return;

    try {
      console.log('[STT Adapter] Initializing...');

      // Create adapter instance
      const adapter = new WhisperSTTAdapter();

      // Set up event listeners
      adapter.on('model_loading', (progress) => {
        console.log('[STT Adapter] Model loading', progress);
        setState(prev => ({
          ...prev,
          modelLoadProgress: progress.progress || 0,
          modelLoadMessage: progress.message || 'Loading...'
        }));
      });

      adapter.on('error', (error: Error) => {
        console.error('[STT Adapter] Error:', error.message);
        setState(prev => ({
          ...prev,
          error: error.message,
          isTranscribing: false
        }));
      });

      // Initialize with config
      const result = await adapter.initialize({
        model: config?.model ?? 'whisper-tiny',
        device: config?.device ?? 'wasm',
        language: config?.language ?? 'en',
        task: config?.task ?? 'transcribe',
        dtype: config?.dtype || 'q4',
        ...config
      });

      if (!result.success) {
        throw new Error('Failed to initialize STT');
      }

      adapterRef.current = adapter;

      setState(prev => ({
        ...prev,
        isInitialized: true,
        error: null
      }));

      // Load the default model
      const defaultModel = config?.model || 'whisper-tiny';
      await loadModel(defaultModel);

      console.log('[STT Adapter] Initialized successfully');
    } catch (err) {
      const error = `STT initialization error: ${err}`;
      setState(prev => ({ ...prev, error }));
      console.error('[STT Adapter]', error);
    }
  }, [state.isInitialized, config]);

  // Load model
  const loadModel = useCallback(async (modelId: string) => {
    if (!adapterRef.current) {
      console.warn('[STT Adapter] Adapter not initialized');
      return;
    }

    try {
      console.log('[STT Adapter] Loading model:', modelId);
      setState(prev => ({ ...prev, isModelLoaded: false, error: null }));

      const result = await adapterRef.current.loadModel(modelId);
      if (!result.success) {
        throw new Error(`Failed to load model: ${modelId}`);
      }

      // Check if model is actually loaded
      const isLoaded = adapterRef.current.isModelLoaded();

      setState(prev => ({
        ...prev,
        isModelLoaded: isLoaded,
        modelLoadProgress: isLoaded ? 100 : prev.modelLoadProgress,
        modelLoadMessage: isLoaded ? 'Model ready!' : prev.modelLoadMessage
      }));

      console.log('[STT Adapter] Model loaded successfully:', modelId);
    } catch (err) {
      const error = `Failed to load model: ${err}`;
      setState(prev => ({ ...prev, error }));
      console.error('[STT Adapter]', error);
    }
  }, []);

  // Transcribe audio
  const transcribe = useCallback(async (audio: Float32Array, options?: { language?: string; task?: 'transcribe' | 'translate' }) => {
    if (!adapterRef.current || !state.isModelLoaded) {
      console.warn('[STT Adapter] Adapter or model not ready');
      return null;
    }

    try {
      setState(prev => ({
        ...prev,
        isTranscribing: true,
        error: null,
        lastTranscription: null
      }));

      console.log('[STT Adapter] Starting transcription...', { audioLength: audio.length });

      const result = await adapterRef.current.transcribe(audio, options);

      if (!result.success) {
        throw new Error('Transcription failed');
      }

      setState(prev => ({
        ...prev,
        isTranscribing: false,
        lastTranscription: result.value
      }));

      console.log('[STT Adapter] Transcription completed:', result.value.text);
      return result.value;

    } catch (err) {
      const error = `Transcription error: ${err}`;
      setState(prev => ({
        ...prev,
        error,
        isTranscribing: false
      }));
      console.error('[STT Adapter]', error);
      return null;
    }
  }, [state.isModelLoaded]);

  // Get available models
  const getAvailableModels = useCallback((): ModelInfo[] => {
    if (!adapterRef.current) return [];
    return adapterRef.current.supportedModels;
  }, []);

  // Get loaded model
  const getLoadedModel = useCallback(() => {
    if (!adapterRef.current) return null;
    return adapterRef.current.getLoadedModel();
  }, []);

  // Get metrics
  const getMetrics = useCallback(() => {
    if (!adapterRef.current) return null;
    return adapterRef.current.getMetrics();
  }, []);

  // Clear last transcription
  const clearTranscription = useCallback(() => {
    setState(prev => ({ ...prev, lastTranscription: null }));
  }, []);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (adapterRef.current) {
        adapterRef.current.destroy().catch(console.error);
        adapterRef.current = null;
      }
    };
  }, []);

  return {
    ...state,
    initialize,
    loadModel,
    transcribe,
    getAvailableModels,
    getLoadedModel,
    getMetrics,
    clearTranscription,
  };
}
