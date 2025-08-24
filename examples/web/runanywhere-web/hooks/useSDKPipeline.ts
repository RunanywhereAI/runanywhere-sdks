'use client';

import { useState, useCallback, useRef, useEffect } from 'react';
import { ServiceRegistry, logger } from '@runanywhere/core';
import { SileroVADAdapter } from '@runanywhere/vad-silero';
import { WhisperSTTAdapter } from '@runanywhere/stt-whisper';
import { WebSpeechTTSAdapter } from '@runanywhere/tts-webspeech';
import { OpenAILLMAdapter } from '@runanywhere/llm-openai';
import { EnhancedVoicePipelineManager } from '@runanywhere/voice';

interface SDKPipelineConfig {
  apiKey?: string;
  useLocalModels?: boolean;
  volume?: number;
  speed?: number;
}

interface ModelDownloadStatus {
  vad: 'idle' | 'downloading' | 'ready' | 'error';
  stt: 'idle' | 'downloading' | 'ready' | 'error';
  tts: 'idle' | 'downloading' | 'ready' | 'error';
  llm: 'idle' | 'downloading' | 'ready' | 'error';
}

export function useSDKPipeline(config: SDKPipelineConfig) {
  const [isListening, setIsListening] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);
  const [transcript, setTranscript] = useState('');
  const [response, setResponse] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [modelStatus, setModelStatus] = useState<ModelDownloadStatus>({
    vad: 'idle',
    stt: 'idle',
    tts: 'idle',
    llm: 'idle',
  });
  const [downloadProgress, setDownloadProgress] = useState<Record<string, number>>({});

  // SDK Adapter instances
  const vadAdapterRef = useRef<SileroVADAdapter | null>(null);
  const sttAdapterRef = useRef<WhisperSTTAdapter | null>(null);
  const ttsAdapterRef = useRef<WebSpeechTTSAdapter | null>(null);
  const llmAdapterRef = useRef<OpenAILLMAdapter | null>(null);
  const pipelineRef = useRef<EnhancedVoicePipelineManager | null>(null);

  // Initialize adapters
  const initializeVAD = useCallback(async () => {
    try {
      setModelStatus(prev => ({ ...prev, vad: 'downloading' }));

      const adapter = new SileroVADAdapter();
      const result = await adapter.initialize();

      if (result.isOk()) {
        vadAdapterRef.current = adapter;
        setModelStatus(prev => ({ ...prev, vad: 'ready' }));
        logger.info('VAD adapter initialized', 'useSDKPipeline');
        return adapter;
      } else {
        throw result.error;
      }
    } catch (err) {
      setModelStatus(prev => ({ ...prev, vad: 'error' }));
      setError(`Failed to initialize VAD: ${err}`);
      logger.error('VAD initialization failed', 'useSDKPipeline', { error: err });
      return null;
    }
  }, []);

  const initializeSTT = useCallback(async (modelId: string = 'whisper-tiny') => {
    try {
      setModelStatus(prev => ({ ...prev, stt: 'downloading' }));

      const adapter = new WhisperSTTAdapter();
      await adapter.initialize();

      // Set up progress tracking
      adapter.on('model_loading', (progress) => {
        setDownloadProgress(prev => ({ ...prev, stt: progress.progress }));
        logger.debug(`STT model loading: ${progress.message}`, 'useSDKPipeline');
      });

      // Load the model
      const result = await adapter.loadModel(modelId);

      if (result.isOk()) {
        sttAdapterRef.current = adapter;
        setModelStatus(prev => ({ ...prev, stt: 'ready' }));
        logger.info(`STT adapter initialized with ${modelId}`, 'useSDKPipeline');
        return adapter;
      } else {
        throw result.error;
      }
    } catch (err) {
      setModelStatus(prev => ({ ...prev, stt: 'error' }));
      setError(`Failed to initialize STT: ${err}`);
      logger.error('STT initialization failed', 'useSDKPipeline', { error: err });
      return null;
    }
  }, []);

  const initializeTTS = useCallback(async () => {
    try {
      setModelStatus(prev => ({ ...prev, tts: 'downloading' }));

      const adapter = new WebSpeechTTSAdapter();
      const result = await adapter.initialize({
        volume: config.volume,
        rate: config.speed,
      });

      if (result.isOk()) {
        ttsAdapterRef.current = adapter;
        setModelStatus(prev => ({ ...prev, tts: 'ready' }));
        logger.info('TTS adapter initialized', 'useSDKPipeline');
        return adapter;
      } else {
        throw result.error;
      }
    } catch (err) {
      setModelStatus(prev => ({ ...prev, tts: 'error' }));
      setError(`Failed to initialize TTS: ${err}`);
      logger.error('TTS initialization failed', 'useSDKPipeline', { error: err });
      return null;
    }
  }, [config.volume, config.speed]);

  const initializeLLM = useCallback(async () => {
    if (!config.apiKey) {
      setModelStatus(prev => ({ ...prev, llm: 'idle' }));
      return null;
    }

    try {
      setModelStatus(prev => ({ ...prev, llm: 'downloading' }));

      const adapter = new OpenAILLMAdapter();
      const result = await adapter.initialize({
        apiKey: config.apiKey,
        model: 'gpt-4-turbo-preview',
        temperature: 0.7,
        maxTokens: 150,
      });

      if (result.isOk()) {
        llmAdapterRef.current = adapter;
        setModelStatus(prev => ({ ...prev, llm: 'ready' }));
        logger.info('LLM adapter initialized', 'useSDKPipeline');
        return adapter;
      } else {
        throw result.error;
      }
    } catch (err) {
      setModelStatus(prev => ({ ...prev, llm: 'error' }));
      setError(`Failed to initialize LLM: ${err}`);
      logger.error('LLM initialization failed', 'useSDKPipeline', { error: err });
      return null;
    }
  }, [config.apiKey]);

  // Initialize full pipeline
  const initializePipeline = useCallback(async () => {
    try {
      // Initialize all adapters
      const [vad, stt, tts, llm] = await Promise.all([
        initializeVAD(),
        initializeSTT(),
        initializeTTS(),
        initializeLLM(),
      ]);

      if (!vad || !stt || !tts) {
        throw new Error('Failed to initialize required adapters');
      }

      // Create pipeline manager
      const pipeline = new EnhancedVoicePipelineManager({
        vad: { adapter: vad },
        stt: { adapter: stt },
        tts: { adapter: tts },
        llm: llm ? { adapter: llm } : undefined,
      });

      // Set up event handlers
      pipeline.on('transcription', (result) => {
        setTranscript(result.text);
        logger.info('Transcription received', 'useSDKPipeline', { text: result.text });
      });

      pipeline.on('llm_response', (result) => {
        setResponse(result.text);
        logger.info('LLM response received', 'useSDKPipeline');
      });

      pipeline.on('error', (err) => {
        setError(err.message);
        logger.error('Pipeline error', 'useSDKPipeline', { error: err });
      });

      pipelineRef.current = pipeline;
      logger.info('Pipeline initialized successfully', 'useSDKPipeline');
    } catch (err) {
      setError(`Failed to initialize pipeline: ${err}`);
      logger.error('Pipeline initialization failed', 'useSDKPipeline', { error: err });
    }
  }, [initializeVAD, initializeSTT, initializeTTS, initializeLLM]);

  // Start/stop listening
  const startListening = useCallback(async () => {
    if (!pipelineRef.current) {
      setError('Pipeline not initialized');
      return;
    }

    setError(null);
    setTranscript('');
    setResponse('');
    setIsListening(true);

    try {
      const result = await pipelineRef.current.start();
      if (result.isErr()) {
        throw result.error;
      }
      logger.info('Started listening', 'useSDKPipeline');
    } catch (err) {
      setError(`Failed to start listening: ${err}`);
      setIsListening(false);
      logger.error('Failed to start listening', 'useSDKPipeline', { error: err });
    }
  }, []);

  const stopListening = useCallback(() => {
    if (pipelineRef.current && isListening) {
      pipelineRef.current.stop();
      setIsListening(false);
      logger.info('Stopped listening', 'useSDKPipeline');
    }
  }, [isListening]);

  const toggleListening = useCallback(() => {
    if (isListening) {
      stopListening();
    } else {
      startListening();
    }
  }, [isListening, startListening, stopListening]);

  // Individual component methods for testing
  const testSTT = useCallback(async (audio: Float32Array) => {
    if (!sttAdapterRef.current) {
      setError('STT not initialized');
      return null;
    }

    try {
      const result = await sttAdapterRef.current.transcribe(audio);
      if (result.isOk()) {
        setTranscript(result.value.text);
        return result.value;
      } else {
        throw result.error;
      }
    } catch (err) {
      setError(`STT error: ${err}`);
      return null;
    }
  }, []);

  const testTTS = useCallback(async (text: string) => {
    if (!ttsAdapterRef.current) {
      setError('TTS not initialized');
      return;
    }

    try {
      const result = await ttsAdapterRef.current.synthesizeAndPlay(text, {
        volume: config.volume,
        rate: config.speed,
      });

      if (result.isErr()) {
        throw result.error;
      }
    } catch (err) {
      setError(`TTS error: ${err}`);
    }
  }, [config.volume, config.speed]);

  const testLLM = useCallback(async (message: string) => {
    if (!llmAdapterRef.current) {
      setError('LLM not initialized - API key required');
      return null;
    }

    try {
      setIsProcessing(true);
      const result = await llmAdapterRef.current.complete([
        { role: 'system', content: 'You are a helpful assistant. Keep responses concise.' },
        { role: 'user', content: message }
      ]);

      if (result.isOk()) {
        setResponse(result.value.text);
        return result.value;
      } else {
        throw result.error;
      }
    } catch (err) {
      setError(`LLM error: ${err}`);
      return null;
    } finally {
      setIsProcessing(false);
    }
  }, []);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      vadAdapterRef.current?.destroy();
      sttAdapterRef.current?.destroy();
      ttsAdapterRef.current?.destroy();
      llmAdapterRef.current?.destroy();
      pipelineRef.current?.destroy();
    };
  }, []);

  return {
    // State
    isListening,
    isProcessing,
    transcript,
    response,
    error,
    modelStatus,
    downloadProgress,

    // Pipeline methods
    initializePipeline,
    startListening,
    stopListening,
    toggleListening,

    // Individual adapter methods
    initializeVAD,
    initializeSTT,
    initializeTTS,
    initializeLLM,
    testSTT,
    testTTS,
    testLLM,
  };
}
