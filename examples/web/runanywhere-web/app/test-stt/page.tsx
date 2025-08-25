'use client';

import { useSTT } from '@/hooks/useSTT';
import { useVADAdapter } from '@/hooks/useVADAdapter';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Progress } from '@/components/ui/progress';
import { Mic, MicOff, Play, Pause, AlertCircle, Activity, FileAudio, Loader2 } from 'lucide-react';
import { useEffect, useState } from 'react';

export default function TestSTTPage() {
  const [logs, setLogs] = useState<string[]>([]);
  const [selectedModel, setSelectedModel] = useState<string>('whisper-tiny');
  const [audioSource, setAudioSource] = useState<'microphone' | 'upload'>('microphone');

  // Add console interceptor for debugging
  useEffect(() => {
    const originalLog = console.log;
    const originalError = console.error;

    console.log = (...args: any[]) => {
      originalLog(...args);
      const message = args.map(arg =>
        typeof arg === 'object' ? JSON.stringify(arg, null, 2) : String(arg)
      ).join(' ');
      if (message.includes('[STT Adapter]')) {
        setLogs(prev => [...prev.slice(-19), `[${new Date().toLocaleTimeString()}] ${message}`]);
      }
    };

    console.error = (...args: any[]) => {
      originalError(...args);
      const message = args.map(arg =>
        typeof arg === 'object' ? JSON.stringify(arg, null, 2) : String(arg)
      ).join(' ');
      if (message.includes('[STT Adapter]')) {
        setLogs(prev => [...prev.slice(-19), `[ERROR ${new Date().toLocaleTimeString()}] ${message}`]);
      }
    };

    return () => {
      console.log = originalLog;
      console.error = originalError;
    };
  }, []);

  const stt = useSTT({
    model: selectedModel as 'whisper-tiny' | 'whisper-base' | 'whisper-small',
    device: 'wasm',
    language: 'en',
    task: 'transcribe'
  });

  const vad = useVADAdapter({
    positiveSpeechThreshold: 0.9,
    negativeSpeechThreshold: 0.75,
    minSpeechDuration: 96,
    preSpeechPadding: 320,
  });

  // Auto-transcribe when VAD detects speech
  useEffect(() => {
    if (vad.speechAudio && stt.isModelLoaded && audioSource === 'microphone') {
      console.log('[Test STT] Auto-transcribing VAD audio');
      stt.transcribe(vad.speechAudio);
    }
  }, [vad.speechAudio, stt.isModelLoaded, stt.transcribe, audioSource]);

  const handleModelChange = async (model: string) => {
    setSelectedModel(model);
    if (stt.isInitialized) {
      await stt.loadModel(model);
    }
  };

  const handleAudioUpload = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file || !stt.isModelLoaded) return;

    try {
      // Convert uploaded file to Float32Array
      const audioContext = new AudioContext({ sampleRate: 16000 });
      const arrayBuffer = await file.arrayBuffer();
      const audioBuffer = await audioContext.decodeAudioData(arrayBuffer);

      // Get the audio data (mono, 16kHz)
      let audioData = audioBuffer.getChannelData(0);

      // Resample to 16kHz if needed
      if (audioBuffer.sampleRate !== 16000) {
        const ratio = audioBuffer.sampleRate / 16000;
        const newLength = Math.floor(audioData.length / ratio);
        const resampledData = new Float32Array(newLength);

        for (let i = 0; i < newLength; i++) {
          resampledData[i] = audioData[Math.floor(i * ratio)];
        }
        audioData = resampledData;
      }

      console.log('[Test STT] Transcribing uploaded audio', { length: audioData.length });
      await stt.transcribe(audioData);
    } catch (error) {
      console.error('[Test STT] Failed to process uploaded audio:', error);
    }
  };

  return (
    <div className="min-h-screen bg-background p-8">
      <div className="max-w-6xl mx-auto space-y-6">
        <div className="text-center space-y-2">
          <h1 className="text-4xl font-bold">Whisper STT Test</h1>
          <p className="text-muted-foreground">
            Testing Speech-to-Text with @runanywhere/stt-whisper and Transformers.js
          </p>
        </div>

        {/* Status Card */}
        <Card>
          <CardHeader>
            <CardTitle>STT Status</CardTitle>
            <CardDescription>
              Real-time speech-to-text status and configuration
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {/* Status Badges */}
            <div className="flex flex-wrap gap-2">
              <Badge variant={stt.isInitialized ? 'default' : 'secondary'}>
                {stt.isInitialized ? '✓ Initialized' : '○ Not Initialized'}
              </Badge>
              <Badge variant={stt.isModelLoaded ? 'default' : 'secondary'}>
                {stt.isModelLoaded ? '✓ Model Loaded' : '○ Model Not Loaded'}
              </Badge>
              <Badge
                variant={stt.isTranscribing ? 'destructive' : 'secondary'}
                className={stt.isTranscribing ? 'animate-pulse' : ''}
              >
                {stt.isTranscribing ? '🔄 Transcribing' : '○ Idle'}
              </Badge>
            </div>

            {/* Model Loading Progress */}
            {stt.modelLoadProgress > 0 && stt.modelLoadProgress < 100 && (
              <div className="space-y-2">
                <div className="flex items-center gap-2">
                  <Loader2 className="w-4 h-4 animate-spin" />
                  <span className="text-sm">{stt.modelLoadMessage}</span>
                </div>
                <Progress value={stt.modelLoadProgress} className="h-2" />
              </div>
            )}

            {/* Error Display */}
            {stt.error && (
              <div className="bg-destructive/10 border border-destructive/20 rounded-lg p-3 flex items-start gap-2">
                <AlertCircle className="w-5 h-5 text-destructive mt-0.5" />
                <div className="flex-1">
                  <p className="text-sm font-medium text-destructive">Error</p>
                  <p className="text-sm text-muted-foreground">{stt.error}</p>
                </div>
              </div>
            )}

            {/* Transcription Result */}
            {stt.lastTranscription && (
              <div className="bg-primary/10 border border-primary/20 rounded-lg p-4">
                <div className="flex justify-between items-start mb-2">
                  <p className="text-sm font-medium">Transcription Result:</p>
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={stt.clearTranscription}
                  >
                    Clear
                  </Button>
                </div>
                <blockquote className="text-lg italic border-l-4 border-primary/30 pl-4 mb-2">
                  "{stt.lastTranscription.text}"
                </blockquote>
                <div className="text-xs text-muted-foreground space-y-1">
                  <p>Language: {stt.lastTranscription.language}</p>
                  <p>Confidence: {(stt.lastTranscription.confidence * 100).toFixed(1)}%</p>
                  <p>Processing Time: {stt.lastTranscription.processingTime}ms</p>
                </div>
              </div>
            )}

            {/* Metrics Display */}
            {stt.isInitialized && (
              <div className="space-y-2">
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => {
                    const metrics = stt.getMetrics();
                    if (metrics) {
                      console.log('[STT Metrics]', metrics);
                      alert(JSON.stringify(metrics, null, 2));
                    }
                  }}
                >
                  <Activity className="w-4 h-4 mr-2" />
                  Show Metrics
                </Button>
              </div>
            )}
          </CardContent>
        </Card>

        {/* Configuration Card */}
        <Card>
          <CardHeader>
            <CardTitle>Configuration</CardTitle>
            <CardDescription>
              Configure STT model and input source
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {/* Model Selection */}
            <div className="space-y-2">
              <label className="text-sm font-medium">Whisper Model</label>
              <Select value={selectedModel} onValueChange={handleModelChange}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="whisper-tiny">Whisper Tiny (39MB, Fast)</SelectItem>
                  <SelectItem value="whisper-base">Whisper Base (74MB, Better)</SelectItem>
                  <SelectItem value="whisper-small">Whisper Small (244MB, Best)</SelectItem>
                </SelectContent>
              </Select>
            </div>

            {/* Audio Source Selection */}
            <div className="space-y-2">
              <label className="text-sm font-medium">Audio Source</label>
              <Select value={audioSource} onValueChange={(value: 'microphone' | 'upload') => setAudioSource(value)}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="microphone">Microphone (with VAD)</SelectItem>
                  <SelectItem value="upload">Audio File Upload</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </CardContent>
        </Card>

        {/* Controls Card */}
        <Card>
          <CardHeader>
            <CardTitle>Controls</CardTitle>
            <CardDescription>
              Test STT functionality with different input methods
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {/* Main Controls */}
            <div className="flex flex-wrap gap-2">
              {!stt.isInitialized && (
                <Button
                  onClick={stt.initialize}
                  variant="outline"
                  disabled={stt.isInitialized}
                >
                  Initialize STT
                </Button>
              )}

              {audioSource === 'microphone' && (
                <>
                  {!vad.isInitialized && (
                    <Button
                      onClick={vad.initialize}
                      variant="outline"
                      disabled={vad.isInitialized}
                    >
                      Initialize VAD
                    </Button>
                  )}

                  {vad.isInitialized && !vad.isListening && (
                    <Button
                      onClick={vad.startListening}
                      variant="default"
                      disabled={!stt.isModelLoaded}
                    >
                      <Mic className="w-4 h-4 mr-2" />
                      Start Listening
                    </Button>
                  )}

                  {vad.isListening && (
                    <Button
                      onClick={vad.stopListening}
                      variant="destructive"
                    >
                      <MicOff className="w-4 h-4 mr-2" />
                      Stop Listening
                    </Button>
                  )}
                </>
              )}

              {audioSource === 'upload' && (
                <div className="flex items-center gap-2">
                  <input
                    type="file"
                    accept="audio/*"
                    onChange={handleAudioUpload}
                    disabled={!stt.isModelLoaded}
                    className="hidden"
                    id="audio-upload"
                  />
                  <Button
                    variant="default"
                    disabled={!stt.isModelLoaded}
                    onClick={() => document.getElementById('audio-upload')?.click()}
                  >
                    <FileAudio className="w-4 h-4 mr-2" />
                    Upload Audio File
                  </Button>
                </div>
              )}
            </div>

            {/* VAD Status for Microphone Mode */}
            {audioSource === 'microphone' && vad.isInitialized && (
              <div className="space-y-2">
                <p className="text-sm font-medium">VAD Status:</p>
                <div className="flex gap-2">
                  <Badge variant={vad.isListening ? 'default' : 'secondary'}>
                    {vad.isListening ? '🎤 Listening' : '○ Not Listening'}
                  </Badge>
                  <Badge
                    variant={vad.isSpeaking ? 'destructive' : 'secondary'}
                    className={vad.isSpeaking ? 'animate-pulse' : ''}
                  >
                    {vad.isSpeaking ? '🗣️ Speaking' : '😶 Silent'}
                  </Badge>
                </div>
              </div>
            )}
          </CardContent>
        </Card>

        {/* Instructions Card */}
        <Card>
          <CardHeader>
            <CardTitle>Instructions</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm text-muted-foreground">
            <p><strong>Microphone Mode:</strong></p>
            <p>1. Click "Initialize STT" to load the Whisper model</p>
            <p>2. Click "Initialize VAD" to set up voice activity detection</p>
            <p>3. Click "Start Listening" to begin recording</p>
            <p>4. Speak clearly - when you stop talking, STT will transcribe automatically</p>
            <br />
            <p><strong>Upload Mode:</strong></p>
            <p>1. Click "Initialize STT" to load the Whisper model</p>
            <p>2. Switch to "Audio File Upload" mode</p>
            <p>3. Click "Upload Audio File" and select an audio file</p>
            <p>4. The transcription will appear automatically</p>
          </CardContent>
        </Card>

        {/* Technical Info */}
        <Card>
          <CardHeader>
            <CardTitle>Technical Details</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm font-mono text-muted-foreground">
            <p>Package: @runanywhere/stt-whisper</p>
            <p>Library: @huggingface/transformers v3.7.2</p>
            <p>Model: {selectedModel} ({
              selectedModel === 'whisper-tiny' ? '39MB' :
              selectedModel === 'whisper-base' ? '74MB' : '244MB'
            })</p>
            <p>Device: WASM (CPU)</p>
            <p>Language: English</p>
            <p>Task: Transcribe</p>
            <p>Sample Rate: 16kHz</p>
          </CardContent>
        </Card>

        {/* Debug Logs */}
        <Card>
          <CardHeader>
            <CardTitle>Debug Logs</CardTitle>
            <CardDescription>
              Real-time STT logs (last 20 entries)
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="bg-muted rounded-lg p-4 h-64 overflow-y-auto">
              {logs.length === 0 ? (
                <p className="text-sm text-muted-foreground">No logs yet...</p>
              ) : (
                <div className="space-y-1">
                  {logs.map((log, i) => (
                    <div
                      key={i}
                      className={`text-xs font-mono ${
                        log.includes('[ERROR') ? 'text-destructive' : 'text-foreground'
                      }`}
                    >
                      {log}
                    </div>
                  ))}
                </div>
              )}
            </div>
            <Button
              size="sm"
              variant="ghost"
              onClick={() => setLogs([])}
              className="mt-2"
            >
              Clear Logs
            </Button>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
