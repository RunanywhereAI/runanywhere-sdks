'use client';

import { useState, useRef } from 'react';
import { WhisperSTTAdapter } from '@runanywhere/stt-whisper';

/**
 * Test STT WITHOUT VAD - Direct audio processing like whisper-web
 * This bypasses VAD completely to test if VAD is causing the ONNX error
 */
export default function TestSTTNoVADPage() {
  const [transcription, setTranscription] = useState<string>('');
  const [isProcessing, setIsProcessing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isRecording, setIsRecording] = useState(false);
  const [status, setStatus] = useState<string>('');

  const sttAdapterRef = useRef<WhisperSTTAdapter | null>(null);
  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const audioChunksRef = useRef<Blob[]>([]);

  // Initialize STT adapter
  const initializeSTT = async () => {
    if (!sttAdapterRef.current) {
      console.log('[No-VAD Test] Initializing STT adapter...');
      setStatus('Initializing STT...');
      const adapter = new WhisperSTTAdapter();

      // Initialize adapter with worker URL
      // Try fp32 dtype - community reports this sometimes fixes the ONNX error
      const initResult = await adapter.initialize({
        model: 'whisper-tiny',  // Back to tiny for faster testing
        device: 'wasm',
        dtype: 'fp32',  // CRITICAL: Try full precision instead of quantized
        language: 'en'
      });

      if (initResult.success) {
        sttAdapterRef.current = adapter;
        console.log('[No-VAD Test] STT initialized successfully');
        setStatus('STT ready');

        // Set up event listeners
        adapter.on('model-loading', (progress: any) => {
          setStatus(`Loading model: ${progress.progress}%`);
        });
      } else {
        console.error('[No-VAD Test] Failed to initialize:', initResult.error);
        setError('Failed to initialize STT');
        setStatus('Failed to initialize');
      }
    }
  };

  // Process audio file upload (like whisper-web)
  const handleFileUpload = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;

    setIsProcessing(true);
    setError(null);
    setTranscription('');
    setStatus('Processing file...');

    try {
      // Initialize STT if needed
      await initializeSTT();

      // Read the audio file
      const audioContext = new AudioContext({ sampleRate: 16000 });
      const arrayBuffer = await file.arrayBuffer();
      const audioBuffer = await audioContext.decodeAudioData(arrayBuffer);

      // Convert to mono Float32Array at 16kHz (NO VAD processing)
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

      console.log('[No-VAD Test] Processing raw audio:', {
        sampleRate: audioBuffer.sampleRate,
        duration: audioBuffer.duration,
        samples: audio.length,
        channels: audioBuffer.numberOfChannels
      });

      setStatus('Transcribing...');

      // Transcribe directly without VAD
      if (sttAdapterRef.current) {
        const result = await sttAdapterRef.current.transcribe(audio);
        if (result.success) {
          const text = result.value?.text || 'No transcription available';
          setTranscription(text);
          setStatus('Transcription complete');
          console.log('[No-VAD Test] SUCCESS! Transcription:', text);
        } else {
          setError('Transcription failed');
          setStatus('Transcription failed');
        }
      }
    } catch (err) {
      console.error('[No-VAD Test] Error:', err);
      setError(`Error: ${err}`);
      setStatus('Error occurred');
    } finally {
      setIsProcessing(false);
    }
  };

  // Record audio without VAD
  const startRecording = async () => {
    try {
      await initializeSTT();

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
      setError(null);
      setTranscription('');
      setStatus('Recording...');
    } catch (err) {
      console.error('[No-VAD Test] Recording error:', err);
      setError(`Recording error: ${err}`);
    }
  };

  const stopRecording = () => {
    if (mediaRecorderRef.current && isRecording) {
      mediaRecorderRef.current.stop();
      mediaRecorderRef.current.stream.getTracks().forEach(track => track.stop());
      setIsRecording(false);
      setStatus('Processing recording...');
    }
  };

  const processRecordedAudio = async (audioBlob: Blob) => {
    setIsProcessing(true);

    try {
      const audioContext = new AudioContext({ sampleRate: 16000 });
      const arrayBuffer = await audioBlob.arrayBuffer();
      const audioBuffer = await audioContext.decodeAudioData(arrayBuffer);

      // Get mono audio at 16kHz
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

      console.log('[No-VAD Test] Processing recorded audio:', {
        duration: audioBuffer.duration,
        samples: audio.length
      });

      setStatus('Transcribing...');

      // Transcribe without VAD
      if (sttAdapterRef.current) {
        const result = await sttAdapterRef.current.transcribe(audio);
        if (result.success) {
          const text = result.value?.text || 'No transcription available';
          setTranscription(text);
          setStatus('Transcription complete');
          console.log('[No-VAD Test] SUCCESS! Transcription:', text);
        } else {
          setError('Transcription failed');
          setStatus('Transcription failed');
        }
      }
    } catch (err) {
      console.error('[No-VAD Test] Processing error:', err);
      setError(`Processing error: ${err}`);
      setStatus('Error occurred');
    } finally {
      setIsProcessing(false);
    }
  };

  return (
    <div className="container mx-auto p-4 max-w-4xl">
      <div className="bg-white rounded-lg shadow-lg p-6">
        <div className="mb-6">
          <h1 className="text-2xl font-bold mb-2">STT Test WITHOUT VAD</h1>
          <p className="text-gray-600">
            Testing Whisper STT by bypassing VAD completely - processes raw audio like whisper-web
          </p>
        </div>

        <div className="space-y-6">
          {/* Status */}
          {status && (
            <div className="p-4 bg-gray-50 rounded-lg">
              <p className="text-sm text-gray-700">Status: {status}</p>
            </div>
          )}

          {/* File Upload */}
          <div className="border rounded-lg p-4">
            <h3 className="text-lg font-semibold mb-3">Option 1: Upload Audio File</h3>
            <div className="flex items-center space-x-2">
              <input
                type="file"
                accept="audio/*"
                onChange={handleFileUpload}
                disabled={isProcessing}
                className="hidden"
                id="audio-upload"
              />
              <label htmlFor="audio-upload">
                <button
                  className="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600 disabled:bg-gray-300 cursor-pointer"
                  disabled={isProcessing}
                  onClick={() => document.getElementById('audio-upload')?.click()}
                >
                  Choose Audio File
                </button>
              </label>
              {isProcessing && <span>Processing...</span>}
            </div>
          </div>

          {/* Recording */}
          <div className="border rounded-lg p-4">
            <h3 className="text-lg font-semibold mb-3">Option 2: Record Audio</h3>
            <div className="flex items-center space-x-2">
              {!isRecording ? (
                <button
                  onClick={startRecording}
                  disabled={isProcessing}
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
              {isRecording && <span className="text-red-500">● Recording...</span>}
            </div>
          </div>

          {/* Results */}
          {error && (
            <div className="p-4 bg-red-50 border border-red-200 rounded-lg">
              <p className="text-red-800">{error}</p>
            </div>
          )}

          {transcription && (
            <div className="p-4 bg-green-50 border border-green-200 rounded-lg">
              <h3 className="font-semibold text-green-800 mb-2">Transcription:</h3>
              <p className="text-green-700">{transcription}</p>
            </div>
          )}

          {/* Info */}
          <div className="p-4 bg-blue-50 border border-blue-200 rounded-lg">
            <h3 className="font-semibold text-blue-800 mb-2">Test Information:</h3>
            <ul className="text-sm text-blue-700 space-y-1">
              <li>• This test bypasses VAD completely</li>
              <li>• Processes raw audio directly like whisper-web</li>
              <li>• If this works → VAD is the problem</li>
              <li>• If this fails → Deeper ONNX/transformers.js issue</li>
            </ul>
          </div>
        </div>
      </div>
    </div>
  );
}
