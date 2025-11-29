'use client';

import { useState, useEffect, useRef } from 'react';
import { useSTTWhisperWeb } from '@/hooks/useSTTWhisperWeb';
import { convertStereoToMono, createAudioContext } from '@runanywhere/stt-whisper-web';
// @ts-ignore - BlobFix from fork uses older TypeScript syntax
import { webmFixDuration } from '@/utils/BlobFix';

export default function TestSTTWhisperWebPage() {
  const [recordedAudio, setRecordedAudio] = useState<Float32Array | null>(null);
  const [audioFileName, setAudioFileName] = useState<string>('');
  const [isRecording, setIsRecording] = useState(false);
  const [mediaRecorder, setMediaRecorder] = useState<MediaRecorder | null>(null);
  const [recordingTime, setRecordingTime] = useState(0);
  const recordingStartTime = useRef<number>(0);

  const {
    isInitialized,
    isTranscribing,
    error,
    lastTranscription,
    isWorkerReady,
    modelLoadingProgress,
    modelLoadingMessage,
    metrics,
    initialize,
    transcribe,
    reset
  } = useSTTWhisperWeb({
    model: 'onnx-community/whisper-tiny',
    device: 'wasm',
    dtype: 'q8'
  });

  useEffect(() => {
    initialize();
  }, []); // FIXED: Empty dependency array - initialize once on mount

  // Recording timer
  useEffect(() => {
    let interval: NodeJS.Timeout;
    if (isRecording) {
      interval = setInterval(() => {
        setRecordingTime(prev => prev + 1);
      }, 1000);
    }
    return () => {
      if (interval) clearInterval(interval);
    };
  }, [isRecording]);

  const handleFileUpload = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;

    setAudioFileName(file.name);
    reset();

    try {
      const audioContext = createAudioContext();
      const arrayBuffer = await file.arrayBuffer();
      const audioBuffer = await audioContext.decodeAudioData(arrayBuffer);

      // CRITICAL: Match fork's audio handling
      let audio: Float32Array;
      if (audioBuffer.numberOfChannels === 2) {
        audio = convertStereoToMono(audioBuffer);
      } else {
        // Use getChannelData(0) directly for mono
        audio = audioBuffer.getChannelData(0);
      }
      setRecordedAudio(audio);

      if (isInitialized && isWorkerReady) {
        await transcribe(audio);
      }
    } catch (err) {
      console.error('File processing error:', err);
    }
  };

  const handleRetranscribe = async () => {
    if (recordedAudio && isInitialized && isWorkerReady) {
      reset();
      await transcribe(recordedAudio);
    }
  };

  const startRecording = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          sampleRate: 16000,
          channelCount: 1,
          echoCancellation: true,
          noiseSuppression: true
        }
      });

      const recorder = new MediaRecorder(stream, {
        mimeType: 'audio/webm;codecs=opus'
      });

      const chunks: Blob[] = [];
      recordingStartTime.current = Date.now(); // Track actual start time

      recorder.ondataavailable = (event) => {
        if (event.data.size > 0) {
          chunks.push(event.data);
        }
      };

      recorder.onstop = async () => {
        const actualDuration = Math.max(1, Math.floor((Date.now() - recordingStartTime.current) / 1000));
        console.log('[DEBUG] Recording stopped, actual duration:', actualDuration, 'seconds');
        const blob = new Blob(chunks, { type: 'audio/webm;codecs=opus' });
        await processRecordedAudioWithDuration(blob, actualDuration);

        // Stop all tracks
        stream.getTracks().forEach(track => track.stop());
      };

      setMediaRecorder(recorder);
      setIsRecording(true);
      setRecordingTime(0);
      setAudioFileName('');
      reset();

      recorder.start(1000); // Collect data every second
    } catch (error) {
      console.error('Error starting recording:', error);
      alert('Error accessing microphone. Please ensure microphone permissions are granted.');
    }
  };

  const stopRecording = () => {
    if (mediaRecorder && mediaRecorder.state === 'recording') {
      mediaRecorder.stop();
      setIsRecording(false);
    }
  };

  const processRecordedAudioWithDuration = async (blob: Blob, duration: number) => {
    try {
      console.log('[DEBUG] processRecordedAudio START', {
        blobSize: blob.size,
        blobType: blob.type,
        duration: duration
      });

      // Apply WebM duration fix if needed (critical for Chrome)
      let fixedBlob = blob;
      if (blob.type === 'audio/webm' || blob.type === 'audio/webm;codecs=opus') {
        console.log('[DEBUG] Applying WebM duration fix', {
          originalSize: blob.size,
          duration: duration * 1000,
          type: blob.type
        });

        try {
          fixedBlob = await webmFixDuration(blob, duration * 1000, blob.type);
          console.log('[DEBUG] WebM fix applied successfully', {
            fixedSize: fixedBlob.size,
            sizeChange: fixedBlob.size - blob.size
          });
        } catch (fixError) {
          console.error('[DEBUG] WebM fix failed:', fixError);
          // Continue with original blob
          fixedBlob = blob;
        }
      }

      console.log('[DEBUG] Creating audio context...');
      const audioContext = createAudioContext();
      console.log('[DEBUG] Audio context created', {
        sampleRate: audioContext.sampleRate,
        state: audioContext.state
      });

      console.log('[DEBUG] Converting blob to ArrayBuffer...');
      const arrayBuffer = await fixedBlob.arrayBuffer();
      console.log('[DEBUG] ArrayBuffer created', {
        byteLength: arrayBuffer.byteLength,
        isValid: arrayBuffer instanceof ArrayBuffer
      });

      console.log('[DEBUG] Decoding audio data...');
      const audioBuffer = await audioContext.decodeAudioData(arrayBuffer);
      console.log('[DEBUG] Audio decoded successfully', {
        duration: audioBuffer.duration,
        length: audioBuffer.length,
        numberOfChannels: audioBuffer.numberOfChannels,
        sampleRate: audioBuffer.sampleRate
      });

      // CRITICAL FIX: Match fork's audio handling exactly
      let audio: Float32Array;
      if (audioBuffer.numberOfChannels === 2) {
        console.log('[DEBUG] Converting stereo to mono...');
        audio = convertStereoToMono(audioBuffer);
      } else {
        // CRITICAL: Use getChannelData(0) directly for mono audio (like fork does)
        console.log('[DEBUG] Using mono audio directly (no copy)...');
        audio = audioBuffer.getChannelData(0);
      }

      console.log('[DEBUG] Audio data ready', {
        audioLength: audio.length,
        audioType: audio.constructor.name,
        numberOfChannels: audioBuffer.numberOfChannels,
        isDirectReference: audioBuffer.numberOfChannels === 1,
        firstSamples: Array.from(audio.slice(0, 5)),
        lastSamples: Array.from(audio.slice(-5)),
        minValue: Math.min(...Array.from(audio.slice(0, Math.min(1000, audio.length)))),
        maxValue: Math.max(...Array.from(audio.slice(0, Math.min(1000, audio.length))))
      });

      setRecordedAudio(audio);
      setAudioFileName(`Recording (${duration}s)`);

      if (isInitialized && isWorkerReady) {
        console.log('[DEBUG] Sending to transcribe...', {
          audioLength: audio.length,
          isInitialized,
          isWorkerReady
        });
        await transcribe(audio);
      } else {
        console.warn('[DEBUG] Not ready to transcribe', {
          isInitialized,
          isWorkerReady
        });
      }
    } catch (error) {
      console.error('[DEBUG] Error in processRecordedAudio:', error);
      console.error('[DEBUG] Error stack:', (error as Error).stack);
      reset();
      alert('Error processing recording. Please try again.');
    }
  };

  return (
    <div className="container mx-auto p-4 max-w-4xl">
      <div className="bg-white rounded-lg shadow-lg p-6">
        <h1 className="text-3xl font-bold mb-6">Whisper-Web Fork Test</h1>

        {/* Status Section */}
        <div className="mb-6 grid grid-cols-1 md:grid-cols-3 gap-4">
          <div className={`p-3 rounded-lg ${isInitialized ? 'bg-green-100' : 'bg-gray-100'}`}>
            <div className="text-sm font-medium text-gray-600">Initialization</div>
            <div className={`font-semibold ${isInitialized ? 'text-green-800' : 'text-gray-800'}`}>
              {isInitialized ? 'Ready' : 'Initializing...'}
            </div>
          </div>

          <div className={`p-3 rounded-lg ${isWorkerReady ? 'bg-green-100' : 'bg-gray-100'}`}>
            <div className="text-sm font-medium text-gray-600">Worker Status</div>
            <div className={`font-semibold ${isWorkerReady ? 'text-green-800' : 'text-gray-800'}`}>
              {isWorkerReady ? 'Ready' : 'Loading...'}
            </div>
          </div>

          <div className="p-3 rounded-lg bg-blue-100">
            <div className="text-sm font-medium text-gray-600">Transcriptions</div>
            <div className="font-semibold text-blue-800">{metrics.totalTranscriptions}</div>
          </div>
        </div>

        {/* Model Loading Progress */}
        {!isWorkerReady && modelLoadingProgress > 0 && (
          <div className="mb-6 p-4 bg-blue-50 border border-blue-200 rounded-lg">
            <div className="flex justify-between items-center mb-2">
              <span className="text-blue-800 font-medium">Loading Model</span>
              <span className="text-blue-600">{Math.round(modelLoadingProgress)}%</span>
            </div>
            <div className="w-full bg-blue-200 rounded-full h-2">
              <div
                className="bg-blue-600 h-2 rounded-full transition-all duration-300"
                style={{ width: `${modelLoadingProgress}%` }}
              ></div>
            </div>
            <div className="text-sm text-blue-600 mt-1">{modelLoadingMessage}</div>
          </div>
        )}

        {/* Audio Input Section */}
        <div className="mb-6">
          <h3 className="text-lg font-semibold mb-3">Audio Input</h3>

          {/* Microphone Recording */}
          <div className="mb-4">
            <h4 className="text-md font-medium mb-2">🎤 Record from Microphone</h4>
            <div className="flex gap-3 items-center">
              {!isRecording ? (
                <button
                  onClick={startRecording}
                  disabled={!isInitialized || !isWorkerReady || isTranscribing}
                  className="px-4 py-2 bg-red-500 text-white rounded-lg hover:bg-red-600 disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
                >
                  <div className="w-3 h-3 bg-white rounded-full"></div>
                  Start Recording
                </button>
              ) : (
                <button
                  onClick={stopRecording}
                  className="px-4 py-2 bg-gray-500 text-white rounded-lg hover:bg-gray-600 flex items-center gap-2"
                >
                  <div className="w-3 h-3 bg-white rounded-sm"></div>
                  Stop Recording
                </button>
              )}

              {isRecording && (
                <div className="flex items-center gap-2">
                  <div className="w-2 h-2 bg-red-500 rounded-full animate-pulse"></div>
                  <span className="text-red-600 font-mono">
                    {Math.floor(recordingTime / 60)}:{(recordingTime % 60).toString().padStart(2, '0')}
                  </span>
                </div>
              )}
            </div>
          </div>

          {/* File Upload */}
          <div>
            <h4 className="text-md font-medium mb-2">📁 Upload Audio File</h4>
            <div className="flex gap-3">
              <input
                type="file"
                accept="audio/*"
                onChange={handleFileUpload}
                disabled={!isInitialized || !isWorkerReady || isTranscribing || isRecording}
                className="flex-1 text-sm text-gray-900 border border-gray-300 rounded-lg cursor-pointer bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
              />
              {recordedAudio && (
                <button
                  onClick={handleRetranscribe}
                  disabled={!isInitialized || !isWorkerReady || isTranscribing || isRecording}
                  className="px-4 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  Re-transcribe
                </button>
              )}
            </div>
          </div>

          {audioFileName && (
            <p className="text-sm text-gray-600 mt-2">Current: {audioFileName}</p>
          )}
        </div>

        {/* Recording Status */}
        {isRecording && (
          <div className="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg">
            <div className="flex items-center">
              <div className="w-4 h-4 bg-red-500 rounded-full animate-pulse mr-3"></div>
              <p className="text-red-800">
                Recording audio... ({Math.floor(recordingTime / 60)}:{(recordingTime % 60).toString().padStart(2, '0')})
              </p>
            </div>
            <p className="text-sm text-red-600 mt-1">Click "Stop Recording" when finished speaking</p>
          </div>
        )}

        {/* Processing Status */}
        {isTranscribing && (
          <div className="mb-6 p-4 bg-yellow-50 border border-yellow-200 rounded-lg">
            <div className="flex items-center">
              <div className="animate-spin rounded-full h-5 w-5 border-b-2 border-yellow-600 mr-3"></div>
              <p className="text-yellow-800">
                Processing audio using whisper-web fork implementation...
              </p>
            </div>
          </div>
        )}

        {/* Error Display */}
        {error && (
          <div className="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg">
            <h3 className="font-semibold text-red-800 mb-2">Error:</h3>
            <p className="text-red-700">{error}</p>
            <button
              onClick={reset}
              className="mt-2 px-3 py-1 bg-red-100 text-red-800 rounded text-sm hover:bg-red-200"
            >
              Clear Error
            </button>
          </div>
        )}

        {/* Transcription Result */}
        {lastTranscription && (
          <div className="mb-6 p-4 bg-green-50 border border-green-200 rounded-lg">
            <h3 className="font-semibold text-green-800 mb-3">Transcription Result:</h3>
            <div className="bg-white p-3 rounded border text-green-900 font-mono text-sm whitespace-pre-wrap">
              {lastTranscription.text}
            </div>

            {lastTranscription.timestamps && lastTranscription.timestamps.length > 0 && (
              <details className="mt-3">
                <summary className="cursor-pointer text-green-700 font-medium">
                  View Timestamps ({lastTranscription.timestamps.length} segments)
                </summary>
                <div className="mt-2 space-y-1 max-h-64 overflow-y-auto">
                  {lastTranscription.timestamps.map((segment: any, index: number) => (
                    <div key={index} className="flex text-sm">
                      <span className="text-green-600 w-20 flex-shrink-0">
                        {segment.start.toFixed(1)}s-{segment.end.toFixed(1)}s
                      </span>
                      <span className="text-green-800">{segment.text}</span>
                    </div>
                  ))}
                </div>
              </details>
            )}

            <div className="mt-3 text-sm text-green-600">
              Confidence: {(lastTranscription.confidence || 1.0).toFixed(2)} |
              Language: {lastTranscription.language || 'auto'} |
              Processing Time: {metrics.avgProcessingTime.toFixed(0)}ms
            </div>
          </div>
        )}

        {/* Implementation Details */}
        <div className="p-4 bg-blue-50 border border-blue-200 rounded-lg">
          <h3 className="font-semibold text-blue-800 mb-3">Implementation Details:</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
            <div>
              <h4 className="font-medium text-blue-700 mb-2">Technical Stack:</h4>
              <ul className="text-blue-600 space-y-1">
                <li>• transformers.js version: 3.7.0 (exact)</li>
                <li>• Device: WASM (like working fork)</li>
                <li>• dtype: q8 quantization</li>
                <li>• Pipeline Factory pattern</li>
                <li>• ES Module worker architecture</li>
              </ul>
            </div>
            <div>
              <h4 className="font-medium text-blue-700 mb-2">Features:</h4>
              <ul className="text-blue-600 space-y-1">
                <li>• Proper model lifecycle management</li>
                <li>• Streaming transcription support</li>
                <li>• Memory-efficient disposal pattern</li>
                <li>• Real-time progress updates</li>
                <li>• Timestamp extraction</li>
              </ul>
            </div>
          </div>

          <div className="mt-4 p-3 bg-white border border-blue-200 rounded">
            <h4 className="font-medium text-blue-800 mb-2">Success Criteria vs Original Fork:</h4>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-2 text-xs">
              <div className={`p-2 rounded ${isInitialized ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'}`}>
                No ONNX Runtime errors: {isInitialized ? '✅' : '❌'}
              </div>
              <div className={`p-2 rounded ${isWorkerReady ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'}`}>
                Worker initializes: {isWorkerReady ? '✅' : '❌'}
              </div>
              <div className={`p-2 rounded ${lastTranscription ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-800'}`}>
                Transcription works: {lastTranscription ? '✅' : '⏳'}
              </div>
              <div className={`p-2 rounded ${error ? 'bg-red-100 text-red-800' : 'bg-green-100 text-green-800'}`}>
                No errors: {error ? '❌' : '✅'}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
