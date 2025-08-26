'use client';

import { useState, useCallback, useRef, useEffect } from 'react';
import { TTSAdapter } from '@runanywhere/tts';
import type { TTSAdapterConfig, VoiceInfo, SynthesisResult } from '@runanywhere/tts';

interface TTSConfig {
  voice?: string;
  rate?: number;
  pitch?: number;
  volume?: number;
  language?: string;
  autoPlay?: boolean;
  engine?: 'web-speech';
}

interface TTSState {
  isInitialized: boolean;
  isSpeaking: boolean;
  error: string | null;
  availableVoices: VoiceInfo[];
  selectedVoice: VoiceInfo | null;
  lastSynthesis: SynthesisResult | null;
}

/**
 * Hook that uses the @runanywhere/tts package
 * This is an example of how to consume the SDK adapter in a React app
 */
export function useTTS(config: TTSConfig = {}) {
  const [state, setState] = useState<TTSState>({
    isInitialized: false,
    isSpeaking: false,
    error: null,
    availableVoices: [],
    selectedVoice: null,
    lastSynthesis: null,
  });

  const adapterRef = useRef<TTSAdapter | null>(null);

  // Initialize TTS
  const initialize = useCallback(async () => {
    if (state.isInitialized) return;

    try {
      console.log('[TTS Adapter] Initializing...');

      // Create adapter instance
      const adapter = new TTSAdapter({
        voice: config.voice || 'default',
        rate: config.rate || 1.0,
        pitch: config.pitch || 1.0,
        volume: config.volume || 1.0,
        language: config.language || 'en-US',
        autoPlay: config.autoPlay !== false, // Default to true
        engine: config.engine || 'web-speech'
      });

      // Set up event listeners
      adapter.on('ready', () => {
        console.log('[TTS Adapter] Ready');
        setState(prev => ({
          ...prev,
          isInitialized: true,
          error: null
        }));
      });

      adapter.on('synthesisStart', ({ text }) => {
        console.log('[TTS Adapter] Synthesis started for text:', text);
      });

      adapter.on('synthesisComplete', (result: SynthesisResult) => {
        console.log('[TTS Adapter] Synthesis completed:', result);
        setState(prev => ({
          ...prev,
          lastSynthesis: result
        }));
      });

      adapter.on('playbackStart', () => {
        console.log('[TTS Adapter] Playback started');
        setState(prev => ({ ...prev, isSpeaking: true }));
      });

      adapter.on('playbackEnd', () => {
        console.log('[TTS Adapter] Playback ended');
        setState(prev => ({ ...prev, isSpeaking: false }));
      });

      adapter.on('voicesChanged', (voices: VoiceInfo[]) => {
        console.log('[TTS Adapter] Voices changed:', voices.length);

        // Find preferred voice or use default
        let selectedVoice = voices[0] || null;

        if (config.voice && config.voice !== 'default') {
          const found = voices.find(v => v.name === config.voice);
          if (found) selectedVoice = found;
        } else if (config.language) {
          const found = voices.find(v => v.language.startsWith(config.language));
          if (found) selectedVoice = found;
        } else {
          // Try to find English voice
          const englishVoice = voices.find(v => v.language.startsWith('en-'));
          if (englishVoice) selectedVoice = englishVoice;
        }

        setState(prev => ({
          ...prev,
          availableVoices: voices,
          selectedVoice
        }));
      });

      adapter.on('error', (error: Error) => {
        console.error('[TTS Adapter] Error:', error);
        setState(prev => ({ ...prev, error: error.message }));
      });

      // Initialize adapter
      const result = await adapter.initialize();

      if (!result.success) {
        throw new Error('Failed to initialize TTS adapter');
      }

      adapterRef.current = adapter;

      // Load voices
      const voices = adapter.getAvailableVoices();
      if (voices.length > 0) {
        // Find preferred voice
        let selectedVoice = voices[0];

        if (config.voice && config.voice !== 'default') {
          const found = voices.find(v => v.name === config.voice);
          if (found) selectedVoice = found;
        } else if (config.language) {
          const found = voices.find(v => v.language.startsWith(config.language));
          if (found) selectedVoice = found;
        } else {
          const englishVoice = voices.find(v => v.language.startsWith('en-'));
          if (englishVoice) selectedVoice = englishVoice;
        }

        setState(prev => ({
          ...prev,
          availableVoices: voices,
          selectedVoice,
          isInitialized: true
        }));
      }

      console.log('[TTS Adapter] Initialized successfully');
    } catch (err) {
      const error = `TTS initialization error: ${err}`;
      setState(prev => ({ ...prev, error }));
      console.error('[TTS Adapter]', error);
    }
  }, [state.isInitialized, config]);

  // Speak text
  const speak = useCallback(async (text: string) => {
    if (!text.trim()) return;

    if (!state.isInitialized) {
      await initialize();
    }

    if (!adapterRef.current) return;

    try {
      console.log('[TTS Adapter] Speaking:', text);
      const result = await adapterRef.current.speak(text, {
        voice: state.selectedVoice?.name || config.voice || 'default',
        rate: config.rate,
        pitch: config.pitch,
        volume: config.volume,
        language: config.language
      });

      if (!result.success) {
        throw result.error;
      }

      console.log('[TTS Adapter] Speech completed');
    } catch (err) {
      const error = `Failed to speak: ${err}`;
      setState(prev => ({ ...prev, error }));
      console.error('[TTS Adapter]', error);
    }
  }, [state.isInitialized, state.selectedVoice, config, initialize]);

  // Stop speaking
  const stop = useCallback(() => {
    if (adapterRef.current) {
      adapterRef.current.cancel();
      setState(prev => ({ ...prev, isSpeaking: false }));
      console.log('[TTS Adapter] Stopped speaking');
    }
  }, []);

  // Pause speaking
  const pause = useCallback(() => {
    if (adapterRef.current) {
      adapterRef.current.pause();
      console.log('[TTS Adapter] Paused speaking');
    }
  }, []);

  // Resume speaking
  const resume = useCallback(() => {
    if (adapterRef.current) {
      adapterRef.current.resume();
      console.log('[TTS Adapter] Resumed speaking');
    }
  }, []);

  // Set voice
  const setVoice = useCallback((voiceName: string) => {
    const voice = state.availableVoices.find(v => v.name === voiceName);
    if (voice && adapterRef.current) {
      setState(prev => ({ ...prev, selectedVoice: voice }));
      adapterRef.current.setVoice(voiceName);
      console.log('[TTS Adapter] Voice changed to:', voiceName);
    }
  }, [state.availableVoices]);

  // Set rate
  const setRate = useCallback((rate: number) => {
    if (adapterRef.current) {
      adapterRef.current.setRate(rate);
      console.log('[TTS Adapter] Rate changed to:', rate);
    }
  }, []);

  // Set pitch
  const setPitch = useCallback((pitch: number) => {
    if (adapterRef.current) {
      adapterRef.current.setPitch(pitch);
      console.log('[TTS Adapter] Pitch changed to:', pitch);
    }
  }, []);

  // Set volume
  const setVolume = useCallback((volume: number) => {
    if (adapterRef.current) {
      adapterRef.current.setVolume(volume);
      console.log('[TTS Adapter] Volume changed to:', volume);
    }
  }, []);

  // Clear error
  const clearError = useCallback(() => {
    setState(prev => ({ ...prev, error: null }));
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
    speak,
    stop,
    pause,
    resume,
    setVoice,
    setRate,
    setPitch,
    setVolume,
    clearError,
  };
}
