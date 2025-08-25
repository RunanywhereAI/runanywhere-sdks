'use client';

import { useState, useCallback, useRef, useEffect } from 'react';

interface TTSConfig {
  voice?: string;
  rate?: number;
  pitch?: number;
  volume?: number;
  language?: string;
}

interface TTSState {
  isInitialized: boolean;
  isSpeaking: boolean;
  error: string | null;
  availableVoices: SpeechSynthesisVoice[];
  selectedVoice: SpeechSynthesisVoice | null;
}

/**
 * Hook for Text-to-Speech using Web Speech API
 * Single responsibility: Convert text to speech
 * IMPORTANT: Does NOT import SDK packages to avoid bundle issues
 */
export function useTTS(config: TTSConfig = {}) {
  const [state, setState] = useState<TTSState>({
    isInitialized: false,
    isSpeaking: false,
    error: null,
    availableVoices: [],
    selectedVoice: null,
  });

  const utteranceRef = useRef<SpeechSynthesisUtterance | null>(null);

  // Initialize TTS
  const initialize = useCallback(async () => {
    if (state.isInitialized) return;

    try {
      if (!('speechSynthesis' in window)) {
        throw new Error('Web Speech API not supported');
      }

      // Load voices
      const loadVoices = () => {
        const voices = window.speechSynthesis.getVoices();
        if (voices.length > 0) {
          // Find preferred voice or use default
          let selectedVoice = voices[0];

          if (config.voice) {
            const found = voices.find(v => v.name === config.voice);
            if (found) selectedVoice = found;
          } else if (config.language) {
            const found = voices.find(v => v.lang.startsWith(config.language));
            if (found) selectedVoice = found;
          } else {
            // Try to find English voice
            const englishVoice = voices.find(v => v.lang.startsWith('en-'));
            if (englishVoice) selectedVoice = englishVoice;
          }

          setState(prev => ({
            ...prev,
            isInitialized: true,
            availableVoices: voices,
            selectedVoice,
            error: null
          }));

          console.log(`[TTS] Initialized with ${voices.length} voices`);
          console.log('[TTS] Selected voice:', selectedVoice.name);
        }
      };

      if (window.speechSynthesis.getVoices().length > 0) {
        loadVoices();
      } else {
        window.speechSynthesis.addEventListener('voiceschanged', loadVoices);
      }
    } catch (err) {
      setState(prev => ({
        ...prev,
        error: `TTS initialization error: ${err}`
      }));
      console.error('[TTS]', err);
    }
  }, [state.isInitialized, config.voice, config.language]);

  // Speak text
  const speak = useCallback(async (text: string) => {
    if (!text.trim()) return;

    if (!state.isInitialized) {
      await initialize();
    }

    if (!('speechSynthesis' in window)) {
      setState(prev => ({
        ...prev,
        error: 'TTS not available'
      }));
      return;
    }

    try {
      // Cancel any ongoing speech
      window.speechSynthesis.cancel();

      const utterance = new SpeechSynthesisUtterance(text);

      // Apply configuration
      if (state.selectedVoice) {
        utterance.voice = state.selectedVoice;
      }
      utterance.rate = config.rate || 1.0;
      utterance.pitch = config.pitch || 1.0;
      utterance.volume = config.volume || 1.0;

      // Set up event listeners
      utterance.onstart = () => {
        setState(prev => ({ ...prev, isSpeaking: true }));
        console.log('[TTS] Started speaking');
      };

      utterance.onend = () => {
        setState(prev => ({ ...prev, isSpeaking: false }));
        console.log('[TTS] Finished speaking');
      };

      utterance.onerror = (event) => {
        setState(prev => ({
          ...prev,
          isSpeaking: false,
          error: `TTS error: ${event.error}`
        }));
        console.error('[TTS] Speech error:', event.error);
      };

      utteranceRef.current = utterance;
      window.speechSynthesis.speak(utterance);

      console.log('[TTS] Speaking:', text);
    } catch (err) {
      setState(prev => ({
        ...prev,
        isSpeaking: false,
        error: `TTS speak error: ${err}`
      }));
      console.error('[TTS]', err);
    }
  }, [state.isInitialized, state.selectedVoice, config, initialize]);

  // Stop speaking
  const stop = useCallback(() => {
    if ('speechSynthesis' in window) {
      window.speechSynthesis.cancel();
      setState(prev => ({ ...prev, isSpeaking: false }));
      console.log('[TTS] Stopped speaking');
    }
  }, []);

  // Pause speaking
  const pause = useCallback(() => {
    if ('speechSynthesis' in window && window.speechSynthesis.speaking) {
      window.speechSynthesis.pause();
      console.log('[TTS] Paused speaking');
    }
  }, []);

  // Resume speaking
  const resume = useCallback(() => {
    if ('speechSynthesis' in window && window.speechSynthesis.paused) {
      window.speechSynthesis.resume();
      console.log('[TTS] Resumed speaking');
    }
  }, []);

  // Set voice
  const setVoice = useCallback((voiceName: string) => {
    const voice = state.availableVoices.find(v => v.name === voiceName);
    if (voice) {
      setState(prev => ({ ...prev, selectedVoice: voice }));
      console.log('[TTS] Voice changed to:', voiceName);
    }
  }, [state.availableVoices]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if ('speechSynthesis' in window) {
        window.speechSynthesis.cancel();
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
  };
}
