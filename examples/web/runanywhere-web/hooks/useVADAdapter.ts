'use client';

import { useState, useCallback, useRef, useEffect } from 'react';
import { SileroVADAdapter } from '@runanywhere/vad-silero';
import type { SileroVADConfig } from '@runanywhere/vad-silero';

interface VADState {
  isInitialized: boolean;
  isListening: boolean;
  isSpeaking: boolean;
  error: string | null;
  speechAudio: Float32Array | null;
}

/**
 * Hook that uses the @runanywhere/vad-silero package
 * This is an example of how to consume the SDK adapter in a React app
 */
export function useVADAdapter(config?: Partial<SileroVADConfig>) {
  const [state, setState] = useState<VADState>({
    isInitialized: false,
    isListening: false,
    isSpeaking: false,
    error: null,
    speechAudio: null,
  });

  const adapterRef = useRef<SileroVADAdapter | null>(null);

  // Initialize VAD
  const initialize = useCallback(async () => {
    if (state.isInitialized) return;

    try {
      console.log('[VAD Adapter] Initializing...');

      // Create adapter instance
      const adapter = new SileroVADAdapter();

      // Set up event listeners
      adapter.on('speech_start', () => {
        console.log('[VAD Adapter] Speech started');
        setState(prev => ({ ...prev, isSpeaking: true }));
      });

      adapter.on('speech_end', (audio: Float32Array) => {
        console.log('[VAD Adapter] Speech ended, audio length:', audio.length);
        setState(prev => ({
          ...prev,
          isSpeaking: false,
          speechAudio: audio
        }));
      });

      adapter.on('vad_misfire', () => {
        console.log('[VAD Adapter] VAD misfire');
      });

      // Initialize with config - no workerUrl needed, SDK handles it internally
      const result = await adapter.initialize({
        positiveSpeechThreshold: config?.positiveSpeechThreshold ?? 0.9,
        negativeSpeechThreshold: config?.negativeSpeechThreshold ?? 0.75,
        minSpeechDuration: config?.minSpeechDuration ?? 96,
        preSpeechPadding: config?.preSpeechPadding ?? 320,
        ...config
      });

      if (!result.success) {
        throw new Error('Failed to initialize VAD');
      }

      adapterRef.current = adapter;

      setState(prev => ({
        ...prev,
        isInitialized: true,
        error: null
      }));

      console.log('[VAD Adapter] Initialized successfully');
    } catch (err) {
      const error = `VAD initialization error: ${err}`;
      setState(prev => ({ ...prev, error }));
      console.error('[VAD Adapter]', error);
    }
  }, [state.isInitialized, config]);

  // Start listening
  const startListening = useCallback(async () => {
    if (!state.isInitialized) {
      await initialize();
    }

    if (state.isListening || !adapterRef.current) return;

    try {
      console.log('[VAD Adapter] Starting...');
      const result = await adapterRef.current.start();

      if (!result.success) {
        throw new Error('Failed to start VAD');
      }

      setState(prev => ({
        ...prev,
        isListening: true,
        error: null
      }));

      console.log('[VAD Adapter] Started listening');
    } catch (err) {
      const error = `Failed to start VAD: ${err}`;
      setState(prev => ({ ...prev, error }));
      console.error('[VAD Adapter]', error);
    }
  }, [state.isInitialized, state.isListening, initialize]);

  // Stop listening
  const stopListening = useCallback(() => {
    if (!adapterRef.current) return;

    adapterRef.current.stop();
    setState(prev => ({
      ...prev,
      isListening: false,
      isSpeaking: false
    }));

    console.log('[VAD Adapter] Stopped listening');
  }, []);

  // Pause VAD
  const pause = useCallback(() => {
    if (!adapterRef.current) return;
    adapterRef.current.pause();
    console.log('[VAD Adapter] Paused');
  }, []);

  // Resume VAD
  const resume = useCallback(() => {
    if (!adapterRef.current) return;
    adapterRef.current.resume();
    console.log('[VAD Adapter] Resumed');
  }, []);

  // Get metrics
  const getMetrics = useCallback(() => {
    if (!adapterRef.current) return null;
    return adapterRef.current.getMetrics();
  }, []);

  // Clear speech audio
  const clearSpeechAudio = useCallback(() => {
    setState(prev => ({ ...prev, speechAudio: null }));
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
    startListening,
    stopListening,
    pause,
    resume,
    getMetrics,
    clearSpeechAudio,
  };
}
