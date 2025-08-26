'use client';

import { useState, useRef, useEffect } from 'react';
import { useSTT } from '@/hooks/useSTT';

/**
 * Simple STT test WITHOUT VAD using the existing useSTT hook
 * This processes raw audio directly, bypassing VAD completely
 */
export default function TestSTTSimplePage() {
  const [audioReady, setAudioReady] = useState(false);
  const [recordedAudio, setRecordedAudio] = useState<Float32Array | null>(null);
  const [isRecording, setIsRecording] = useState(false);
  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const audioChunksRef = useRef<Blob[]>([]);

  const {
    isInitialized,
    isModelLoaded,
    isTranscribing,
    error,
    lastTranscription,
    modelLoadProgress,
    modelLoadMessage,
    initialize,
    transcribe,
  } = useSTT({
    model: 'whisper-tiny',
    device: 'wasm',
    dtype: 'q8',  // Simple string dtype
    language: 'en',
  });

  // Initialize on mount
  useEffect(() => {
    initialize();
  }, []);

  // Process audio file upload
  const handleFileUpload = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;

    try {
      console.log('[Simple Test] Processing file:', file.name);

      // Decode audio file to Float32Array
      const audioContext = new AudioContext({ sampleRate: 16000 });
      const arrayBuffer = await file.arrayBuffer();
      const audioBuffer = await audioContext.decodeAudioData(arrayBuffer);

      // Convert to mono Float32Array
      let audio: Float32Array;
      if (audioBuffer.numberOfChannels === 2) {
        const left = audioBuffer.getChannelData(0);
        const right = audioBuffer.getChannelData(1);
        audio = new Float32Array(left.length);
        for (let i = 0; i < left.length; i++) {
          audio[i] = (left[i] + right[i]) / 2;
        }
      } else {
        audio = audioBuffer.getChannelData(0);
      }

      console.log('[Simple Test] Audio prepared:', {
        duration: audioBuffer.duration,
        samples: audio.length,
        sampleRate: audioBuffer.sampleRate
      });

      setRecordedAudio(audio);
      setAudioReady(true);

      // Automatically transcribe
      if (isModelLoaded) {
        await transcribe(audio);
      }
    } catch (err) {
      console.error('[Simple Test] File processing error:', err);
    }
  };

  // Start recording
  const startRecording = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const mediaRecorder = new MediaRecorder(stream);

      audioChunksRef.current = [];

      mediaRecorder.ondataavailable = (event) => {
        audioChunksRef.current.push(event.data);
      };

      mediaRecorder.onstop = async () => {
        const audioBlob = new Blob(audioChunksRef.current, { type: 'audio/wav' });
        await processRecordedAudio(audioBlob);
      };

      mediaRecorder.start();
      mediaRecorderRef.current = mediaRecorder;
      setIsRecording(true);
      console.log('[Simple Test] Recording started');
    } catch (err) {
      console.error('[Simple Test] Recording error:', err);
    }
  };

  // Stop recording
  const stopRecording = () => {
    if (mediaRecorderRef.current && isRecording) {
      mediaRecorderRef.current.stop();
      mediaRecorderRef.current.stream.getTracks().forEach(track => track.stop());
      setIsRecording(false);
      console.log('[Simple Test] Recording stopped');
    }
  };

  // Process recorded audio
  const processRecordedAudio = async (audioBlob: Blob) => {
    try {
      const audioContext = new AudioContext({ sampleRate: 16000 });
      const arrayBuffer = await audioBlob.arrayBuffer();
      const audioBuffer = await audioContext.decodeAudioData(arrayBuffer);

      // Convert to mono Float32Array
      let audio: Float32Array;
      if (audioBuffer.numberOfChannels === 2) {
        const left = audioBuffer.getChannelData(0);
        const right = audioBuffer.getChannelData(1);
        audio = new Float32Array(left.length);
        for (let i = 0; i < left.length; i++) {
          audio[i] = (left[i] + right[i]) / 2;
        }
      } else {
        audio = audioBuffer.getChannelData(0);
      }

      console.log('[Simple Test] Recorded audio processed:', {
        duration: audioBuffer.duration,
        samples: audio.length
      });

      setRecordedAudio(audio);
      setAudioReady(true);

      // Transcribe if model is ready
      if (isModelLoaded) {
        await transcribe(audio);
      }
    } catch (err) {
      console.error('[Simple Test] Audio processing error:', err);
    }
  };

  // Retry transcription with recorded audio
  const retryTranscription = async () => {
    if (recordedAudio && isModelLoaded) {
      await transcribe(recordedAudio);
    }
  };

  return (
    <div className="container mx-auto p-4 max-w-4xl">
      <div className="bg-white rounded-lg shadow-lg p-6">
        <h1 className="text-2xl font-bold mb-4">Simple STT Test (No VAD)</h1>

        {/* Status */}
        <div className="mb-6 space-y-2">
          <div className="flex items-center space-x-2">
            <span className={`w-3 h-3 rounded-full ${isInitialized ? 'bg-green-500' : 'bg-gray-300'}`}></span>
            <span>Adapter Initialized</span>
          </div>
          <div className="flex items-center space-x-2">
            <span className={`w-3 h-3 rounded-full ${isModelLoaded ? 'bg-green-500' : 'bg-gray-300'}`}></span>
            <span>Model Loaded</span>
          </div>
          {modelLoadProgress > 0 && modelLoadProgress < 100 && (
            <div className="text-sm text-gray-600">
              {modelLoadMessage} ({modelLoadProgress}%)
            </div>
          )}
        </div>

        {/* File Upload */}
        <div className="mb-6">
          <h3 className="text-lg font-semibold mb-2">Upload Audio File</h3>
          <input
            type="file"
            accept="audio/*"
            onChange={handleFileUpload}
            disabled={!isModelLoaded || isTranscribing}
            className="block w-full text-sm text-gray-900 border border-gray-300 rounded-lg cursor-pointer bg-gray-50 focus:outline-none"
          />
        </div>

        {/* Recording */}
        <div className="mb-6">
          <h3 className="text-lg font-semibold mb-2">Record Audio</h3>
          <div className="flex space-x-2">
            {!isRecording ? (
              <button
                onClick={startRecording}
                disabled={!isModelLoaded || isTranscribing}
                className="px-4 py-2 bg-green-500 text-white rounded hover:bg-green-600 disabled:bg-gray-300"
              >
                Start Recording
              </button>
            ) : (
              <button
                onClick={stopRecording}
                className="px-4 py-2 bg-red-500 text-white rounded hover:bg-red-600"
              >
                Stop Recording
              </button>
            )}
            {audioReady && !isTranscribing && (
              <button
                onClick={retryTranscription}
                className="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600"
              >
                Retry Transcription
              </button>
            )}
          </div>
          {isRecording && <p className="mt-2 text-red-500">● Recording...</p>}
        </div>

        {/* Processing Status */}
        {isTranscribing && (
          <div className="mb-6 p-4 bg-yellow-50 border border-yellow-200 rounded">
            <p className="text-yellow-800">Processing audio...</p>
          </div>
        )}

        {/* Error */}
        {error && (
          <div className="mb-6 p-4 bg-red-50 border border-red-200 rounded">
            <p className="text-red-800">{error}</p>
          </div>
        )}

        {/* Transcription Result */}
        {lastTranscription && (
          <div className="mb-6 p-4 bg-green-50 border border-green-200 rounded">
            <h3 className="font-semibold text-green-800 mb-2">Transcription:</h3>
            <p className="text-green-700">{lastTranscription.text}</p>
            {lastTranscription.confidence && (
              <p className="text-sm text-green-600 mt-2">
                Confidence: {(lastTranscription.confidence * 100).toFixed(1)}%
              </p>
            )}
          </div>
        )}

        {/* Info */}
        <div className="p-4 bg-blue-50 border border-blue-200 rounded">
          <h3 className="font-semibold text-blue-800 mb-2">Test Information:</h3>
          <ul className="text-sm text-blue-700 space-y-1">
            <li>• Uses existing useSTT hook with simple configuration</li>
            <li>• Processes raw audio without VAD</li>
            <li>• dtype: simple string ("q8")</li>
            <li>• device: "wasm"</li>
            <li>• If this works → VAD is definitely the problem</li>
          </ul>
        </div>
      </div>
    </div>
  );
}
