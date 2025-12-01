'use client';

import { useVADAdapter } from '@/hooks/useVADAdapter';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Mic, MicOff, Play, Pause, AlertCircle, Activity } from 'lucide-react';
import { useEffect, useState } from 'react';

export default function TestVADPage() {
  const [logs, setLogs] = useState<string[]>([]);

  // Add console interceptor for debugging
  useEffect(() => {
    const originalLog = console.log;
    const originalError = console.error;

    console.log = (...args: any[]) => {
      originalLog(...args);
      const message = args.map(arg =>
        typeof arg === 'object' ? JSON.stringify(arg, null, 2) : String(arg)
      ).join(' ');
      if (message.includes('[VAD Adapter]')) {
        setLogs(prev => [...prev.slice(-19), `[${new Date().toLocaleTimeString()}] ${message}`]);
      }
    };

    console.error = (...args: any[]) => {
      originalError(...args);
      const message = args.map(arg =>
        typeof arg === 'object' ? JSON.stringify(arg, null, 2) : String(arg)
      ).join(' ');
      if (message.includes('[VAD Adapter]')) {
        setLogs(prev => [...prev.slice(-19), `[ERROR ${new Date().toLocaleTimeString()}] ${message}`]);
      }
    };

    return () => {
      console.log = originalLog;
      console.error = originalError;
    };
  }, []);

  const vad = useVADAdapter({
    positiveSpeechThreshold: 0.9,
    negativeSpeechThreshold: 0.75,
    minSpeechDuration: 96,
    preSpeechPadding: 320,
  });

  return (
    <div className="min-h-screen bg-background p-8">
      <div className="max-w-4xl mx-auto space-y-6">
        <div className="text-center space-y-2">
          <h1 className="text-4xl font-bold">Silero VAD Test</h1>
          <p className="text-muted-foreground">
            Testing Voice Activity Detection with @runanywhere/vad-silero
          </p>
        </div>

        {/* Status Card */}
        <Card>
          <CardHeader>
            <CardTitle>VAD Status</CardTitle>
            <CardDescription>
              Real-time voice activity detection status
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {/* Status Badges */}
            <div className="flex flex-wrap gap-2">
              <Badge variant={vad.isInitialized ? 'default' : 'secondary'}>
                {vad.isInitialized ? '✓ Initialized' : '○ Not Initialized'}
              </Badge>
              <Badge variant={vad.isListening ? 'default' : 'secondary'}>
                {vad.isListening ? '✓ Listening' : '○ Not Listening'}
              </Badge>
              <Badge
                variant={vad.isSpeaking ? 'destructive' : 'secondary'}
                className={vad.isSpeaking ? 'animate-pulse' : ''}
              >
                {vad.isSpeaking ? '🔴 Speaking' : '○ Silent'}
              </Badge>
            </div>

            {/* Error Display */}
            {vad.error && (
              <div className="bg-destructive/10 border border-destructive/20 rounded-lg p-3 flex items-start gap-2">
                <AlertCircle className="w-5 h-5 text-destructive mt-0.5" />
                <div className="flex-1">
                  <p className="text-sm font-medium text-destructive">Error</p>
                  <p className="text-sm text-muted-foreground">{vad.error}</p>
                </div>
              </div>
            )}

            {/* Speech Audio Info */}
            {vad.speechAudio && (
              <div className="bg-primary/10 border border-primary/20 rounded-lg p-3">
                <p className="text-sm font-medium">Speech Detected!</p>
                <p className="text-sm text-muted-foreground">
                  Audio buffer length: {vad.speechAudio.length} samples
                  ({(vad.speechAudio.length / 16000).toFixed(2)}s at 16kHz)
                </p>
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={vad.clearSpeechAudio}
                  className="mt-2"
                >
                  Clear Audio
                </Button>
              </div>
            )}

            {/* Metrics Display */}
            {vad.isInitialized && (
              <div className="space-y-2">
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => {
                    const metrics = vad.getMetrics();
                    if (metrics) {
                      console.log('[VAD Metrics]', metrics);
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

        {/* Control Card */}
        <Card>
          <CardHeader>
            <CardTitle>Controls</CardTitle>
            <CardDescription>
              Test VAD functionality with these controls
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {/* Main Controls */}
            <div className="flex flex-wrap gap-2">
              {!vad.isInitialized && (
                <Button
                  onClick={vad.initialize}
                  variant="outline"
                >
                  Initialize VAD
                </Button>
              )}

              {vad.isInitialized && !vad.isListening && (
                <Button
                  onClick={vad.startListening}
                  variant="default"
                >
                  <Mic className="w-4 h-4 mr-2" />
                  Start Listening
                </Button>
              )}

              {vad.isListening && (
                <>
                  <Button
                    onClick={vad.stopListening}
                    variant="destructive"
                  >
                    <MicOff className="w-4 h-4 mr-2" />
                    Stop Listening
                  </Button>

                  <Button
                    onClick={vad.pause}
                    variant="outline"
                  >
                    <Pause className="w-4 h-4 mr-2" />
                    Pause
                  </Button>

                  <Button
                    onClick={vad.resume}
                    variant="outline"
                  >
                    <Play className="w-4 h-4 mr-2" />
                    Resume
                  </Button>
                </>
              )}
            </div>
          </CardContent>
        </Card>

        {/* Instructions Card */}
        <Card>
          <CardHeader>
            <CardTitle>Instructions</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm text-muted-foreground">
            <p>1. Click "Initialize VAD" to set up the Silero VAD adapter</p>
            <p>2. Click "Start Listening" to begin voice activity detection</p>
            <p>3. Speak into your microphone - the "Speaking" badge will light up</p>
            <p>4. When you stop speaking, the audio will be captured</p>
            <p>5. Use "Show Metrics" to see VAD statistics</p>
            <p>6. Check the browser console for detailed logs</p>
          </CardContent>
        </Card>

        {/* Technical Info */}
        <Card>
          <CardHeader>
            <CardTitle>Technical Details</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm font-mono text-muted-foreground">
            <p>Package: @runanywhere/vad-silero</p>
            <p>Model: Silero VAD v5</p>
            <p>Positive Threshold: 0.9</p>
            <p>Negative Threshold: 0.75</p>
            <p>Min Speech Duration: 96ms (~3 frames)</p>
            <p>Pre-Speech Padding: 320ms (~10 frames)</p>
          </CardContent>
        </Card>

        {/* Debug Logs */}
        <Card>
          <CardHeader>
            <CardTitle>Debug Logs</CardTitle>
            <CardDescription>
              Real-time VAD logs (last 20 entries)
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
