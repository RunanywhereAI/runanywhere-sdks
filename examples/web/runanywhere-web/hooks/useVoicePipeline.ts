'use client';

import { useState, useCallback, useEffect } from 'react';
import { useVADAdapter } from './useVADAdapter';
import { useSTT } from './useSTT';
import { useLLMAdapter } from './useLLM';
import { useTTS } from './useTTS';
import type { SileroVADConfig } from '@runanywhere/vad-silero';

interface VoicePipelineConfig {
  // VAD config - now using Silero VAD
  enableVAD?: boolean;
  vadConfig?: Partial<SileroVADConfig>;

  // STT config
  sttModel?: string;
  sttLanguage?: string;

  // LLM config
  enableLLM?: boolean;
  apiKey?: string;
  llmModel?: string;
  systemPrompt?: string;

  // TTS config
  enableTTS?: boolean;
  autoPlayTTS?: boolean;
  ttsVoice?: string;
  ttsRate?: number;
}

interface VoicePipelineState {
  isInitialized: boolean;
  isListening: boolean;
  isProcessing: boolean;
  error: string | null;
  transcript: string;
  llmResponse: string;
}

/**
 * Main orchestrator hook for the complete voice pipeline
 * Coordinates between VAD, STT, LLM, and TTS
 */
export function useVoicePipeline(config: VoicePipelineConfig = {}) {
  const [state, setState] = useState<VoicePipelineState>({
    isInitialized: false,
    isListening: false,
    isProcessing: false,
    error: null,
    transcript: '',
    llmResponse: '',
  });

  // Initialize individual hooks - using real Silero VAD
  const vad = useVADAdapter({
    positiveSpeechThreshold: config.vadConfig?.positiveSpeechThreshold ?? 0.9,
    negativeSpeechThreshold: config.vadConfig?.negativeSpeechThreshold ?? 0.75,
    minSpeechDuration: config.vadConfig?.minSpeechDuration ?? 96,
    preSpeechPadding: config.vadConfig?.preSpeechPadding ?? 320,
    ...config.vadConfig
  });

  const stt = useSTT({
    model: config.sttModel as 'whisper-tiny' | 'whisper-base' | 'whisper-small' | undefined,
    language: config.sttLanguage,
  });

  const llm = useLLMAdapter({
    defaultModel: config.llmModel,
    systemPrompt: config.systemPrompt,
  });

  const tts = useTTS({
    voice: config.ttsVoice,
    rate: config.ttsRate,
  });

  // Initialize all components
  const initialize = useCallback(async () => {
    if (state.isInitialized) return;

    console.log('[VoicePipeline] Initializing...');

    try {
      // Initialize all components in parallel
      const initPromises = [];

      if (config.enableVAD !== false) {
        initPromises.push(vad.initialize());
      }

      initPromises.push(stt.initialize());

      if (config.enableLLM && config.apiKey) {
        initPromises.push(llm.initialize(config.apiKey));
      }

      if (config.enableTTS !== false) {
        initPromises.push(tts.initialize());
      }

      await Promise.all(initPromises);

      setState(prev => ({
        ...prev,
        isInitialized: true,
        error: null
      }));

      console.log('[VoicePipeline] Initialized successfully');
    } catch (err) {
      const error = `Pipeline initialization error: ${err}`;
      setState(prev => ({ ...prev, error }));
      console.error('[VoicePipeline]', error);
    }
  }, [state.isInitialized, config, vad, stt, llm, tts]);

  // Start listening
  const startListening = useCallback(async () => {
    if (!state.isInitialized) {
      await initialize();
    }

    if (state.isListening) return;

    console.log('[VoicePipeline] Starting...');

    try {
      // Start VAD if enabled
      if (config.enableVAD !== false) {
        await vad.startListening();
      }

      // VAD adapter handles audio internally, no need for stream passing
      // STT will be triggered by speech events from VAD
      console.log('[VoicePipeline] VAD started, waiting for speech events...');

      setState(prev => ({
        ...prev,
        isListening: true,
        error: null
      }));

    } catch (err) {
      const error = `Failed to start pipeline: ${err}`;
      setState(prev => ({ ...prev, error }));
      console.error('[VoicePipeline]', error);
    }
  }, [state.isInitialized, state.isListening, config.enableVAD, vad, stt, initialize]);

  // Stop listening
  const stopListening = useCallback(() => {
    console.log('[VoicePipeline] Stopping...');

    if (config.enableVAD !== false) {
      vad.stopListening();
    }

    setState(prev => ({
      ...prev,
      isListening: false
    }));
  }, [config.enableVAD, vad]);

  // Process transcript through LLM and TTS
  const processTranscript = useCallback(async (text: string) => {
    if (!text.trim()) return;

    setState(prev => ({
      ...prev,
      isProcessing: true,
      transcript: text
    }));

    try {
      // Send to LLM if enabled
      if (config.enableLLM && config.apiKey) {
        const response = await llm.sendMessage(text);

        if (response) {
          setState(prev => ({
            ...prev,
            llmResponse: response
          }));

          // Auto-play TTS if enabled
          if (config.autoPlayTTS && config.enableTTS !== false) {
            await tts.speak(response);
          }
        }
      }
    } catch (err) {
      console.error('[VoicePipeline] Process error:', err);
    } finally {
      setState(prev => ({
        ...prev,
        isProcessing: false
      }));
    }
  }, [config, llm, tts]);

  // Watch for speech audio from VAD and send to STT
  useEffect(() => {
    if (vad.speechAudio) {
      console.log('[VoicePipeline] Speech detected, processing audio...');
      // Convert Float32Array to audio blob and send to STT
      // For now, log that speech was detected
      console.log(`[VoicePipeline] Audio length: ${vad.speechAudio.length} samples`);
      vad.clearSpeechAudio();
    }
  }, [vad.speechAudio, vad.clearSpeechAudio]);

  // Watch for transcription changes
  useEffect(() => {
    if (stt.lastTranscription?.text) {
      processTranscript(stt.lastTranscription.text);
    }
  }, [stt.lastTranscription, processTranscript]);

  // Update error state from components
  useEffect(() => {
    const errors = [
      vad.error,
      stt.error,
      llm.error,
      tts.error
    ].filter(Boolean);

    if (errors.length > 0) {
      setState(prev => ({
        ...prev,
        error: errors.join('; ')
      }));
    }
  }, [vad.error, stt.error, llm.error, tts.error]);

  // Update speaking state
  useEffect(() => {
    setState(prev => ({
      ...prev,
      isProcessing: stt.isTranscribing || llm.isProcessing || tts.isSpeaking
    }));
  }, [stt.isTranscribing, llm.isProcessing, tts.isSpeaking]);

  return {
    // Combined state
    ...state,

    // Individual hook states (for detailed UI)
    vad: {
      isInitialized: vad.isInitialized,
      isListening: vad.isListening,
      isSpeaking: vad.isSpeaking,
      error: vad.error,
    },
    stt: {
      isInitialized: stt.isInitialized,
      isTranscribing: stt.isTranscribing,
      isModelLoaded: stt.isModelLoaded,
      modelLoadProgress: stt.modelLoadProgress,
      transcript: stt.lastTranscription?.text || '',
      error: stt.error,
    },
    llm: {
      isInitialized: llm.isInitialized,
      isProcessing: llm.isProcessing,
      response: llm.response,
      conversationHistory: llm.conversationHistory,
      error: llm.error,
    },
    tts: {
      isInitialized: tts.isInitialized,
      isSpeaking: tts.isSpeaking,
      availableVoices: tts.availableVoices,
      selectedVoice: tts.selectedVoice,
      error: tts.error,
    },

    // Actions
    initialize,
    startListening,
    stopListening,

    // Direct component actions for testing
    testSTT: stt.transcribe,
    testLLM: llm.sendMessage,
    testTTS: tts.speak,
    clearTranscript: stt.clearTranscription,
    clearLLMHistory: llm.clearHistory,
    stopTTS: tts.stop,
  };
}
