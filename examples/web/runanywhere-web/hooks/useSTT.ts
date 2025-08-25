'use client';

import { useState, useCallback, useRef, useEffect } from 'react';

interface STTConfig {
  model?: string;
  language?: string;
  task?: 'transcribe' | 'translate';
}

interface STTState {
  isInitialized: boolean;
  isTranscribing: boolean;
  transcript: string;
  error: string | null;
  modelStatus: 'idle' | 'downloading' | 'ready' | 'error';
  downloadProgress: number;
}

/**
 * Hook for Speech-to-Text using Whisper via Web Worker
 * Single responsibility: Convert audio to text
 * IMPORTANT: Does NOT import transformers or SDK packages directly
 */
export function useSTT(config: STTConfig = {}) {
  const [state, setState] = useState<STTState>({
    isInitialized: false,
    isTranscribing: false,
    transcript: '',
    error: null,
    modelStatus: 'idle',
    downloadProgress: 0,
  });

  const workerRef = useRef<Worker | null>(null);
  const modelRef = useRef<string>(config.model || 'whisper-tiny');

  // Initialize STT Worker (no SDK imports!)
  const initialize = useCallback(async () => {
    if (state.isInitialized) return;

    try {
      setState(prev => ({ ...prev, modelStatus: 'downloading' }));

      // Create worker for Whisper STT
      const worker = new Worker('/worker-B8AxjfLB.js', { type: 'module' });

      worker.addEventListener('message', (event) => {
        const message = event.data;
        console.log('[STT Worker]', message);

        switch (message.status) {
          case 'progress':
            setState(prev => ({
              ...prev,
              downloadProgress: message.progress || 0
            }));
            break;

          case 'ready':
            setState(prev => ({
              ...prev,
              modelStatus: 'ready',
              isInitialized: true,
              error: null
            }));
            console.log('[STT] Model ready');
            break;

          case 'complete':
            if (message.data?.text) {
              setState(prev => ({
                ...prev,
                transcript: message.data.text,
                isTranscribing: false
              }));
              console.log('[STT] Transcription:', message.data.text);
            }
            break;

          case 'error':
            setState(prev => ({
              ...prev,
              modelStatus: 'error',
              error: `STT error: ${message.data?.message || 'Unknown error'}`,
              isTranscribing: false
            }));
            break;
        }
      });

      worker.addEventListener('error', (error) => {
        console.error('[STT] Worker error:', error);
        setState(prev => ({
          ...prev,
          modelStatus: 'error',
          error: `Worker error: ${error.message}`,
          isTranscribing: false
        }));
      });

      workerRef.current = worker;

      // Initialize model with test audio
      const testAudio = new Float32Array(16000);
      worker.postMessage({
        audio: testAudio,
        model: `Xenova/${modelRef.current}`,
        dtype: { encoder_model: 'fp32', decoder_model_merged: 'q4' },
        gpu: false,
        subtask: config.task || 'transcribe',
        language: config.language || null
      });

    } catch (err) {
      setState(prev => ({
        ...prev,
        modelStatus: 'error',
        error: `STT initialization error: ${err}`
      }));
      console.error('[STT]', err);
    }
  }, [state.isInitialized, config.task, config.language]);

  // Transcribe audio
  const transcribe = useCallback(async (audioData: Float32Array) => {
    if (!workerRef.current || state.modelStatus !== 'ready') {
      console.error('[STT] Not ready to transcribe');
      return;
    }

    setState(prev => ({
      ...prev,
      isTranscribing: true,
      error: null
    }));

    try {
      workerRef.current.postMessage({
        audio: audioData,
        model: `Xenova/${modelRef.current}`,
        dtype: { encoder_model: 'fp32', decoder_model_merged: 'q4' },
        gpu: false,
        subtask: config.task || 'transcribe',
        language: config.language || null
      });

      console.log('[STT] Transcribing audio...');
    } catch (err) {
      setState(prev => ({
        ...prev,
        isTranscribing: false,
        error: `Transcription error: ${err}`
      }));
      console.error('[STT]', err);
    }
  }, [state.modelStatus, config.task, config.language]);

  // Transcribe from MediaStream
  const transcribeStream = useCallback(async (stream: MediaStream) => {
    if (!stream) {
      console.error('[STT] No stream provided');
      return;
    }

    try {
      const audioContext = new AudioContext({ sampleRate: 16000 });
      const source = audioContext.createMediaStreamSource(stream);
      const processor = audioContext.createScriptProcessor(4096, 1, 1);

      const audioChunks: Float32Array[] = [];

      processor.onaudioprocess = (e) => {
        const inputData = e.inputBuffer.getChannelData(0);
        audioChunks.push(new Float32Array(inputData));
      };

      source.connect(processor);
      processor.connect(audioContext.destination);

      // Record for 5 seconds (demo)
      setTimeout(() => {
        processor.disconnect();
        source.disconnect();

        // Concatenate audio chunks
        const totalLength = audioChunks.reduce((acc, chunk) => acc + chunk.length, 0);
        const audioData = new Float32Array(totalLength);
        let offset = 0;
        for (const chunk of audioChunks) {
          audioData.set(chunk, offset);
          offset += chunk.length;
        }

        // Transcribe the audio
        transcribe(audioData);
      }, 5000);

      console.log('[STT] Recording audio for transcription...');
    } catch (err) {
      setState(prev => ({
        ...prev,
        error: `Stream transcription error: ${err}`
      }));
      console.error('[STT]', err);
    }
  }, [transcribe]);

  // Clear transcript
  const clearTranscript = useCallback(() => {
    setState(prev => ({ ...prev, transcript: '' }));
  }, []);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (workerRef.current) {
        workerRef.current.terminate();
        workerRef.current = null;
      }
    };
  }, []);

  return {
    ...state,
    initialize,
    transcribe,
    transcribeStream,
    clearTranscript,
  };
}
