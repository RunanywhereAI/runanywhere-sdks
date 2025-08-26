'use client';

import { useTTS } from '@/hooks/useTTS';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Slider } from '@/components/ui/slider';
import { Textarea } from '@/components/ui/textarea';
import { Volume2, VolumeX, Play, Pause, Square, AlertCircle, Settings, Mic } from 'lucide-react';
import { useEffect, useState } from 'react';

export default function TestTTSPage() {
  const [logs, setLogs] = useState<string[]>([]);
  const [textInput, setTextInput] = useState('Hello! This is a test of the Text-to-Speech system using the RunAnywhere SDK.');
  const [selectedVoice, setSelectedVoice] = useState<string>('');
  const [rate, setRate] = useState([1.0]);
  const [pitch, setPitch] = useState([1.0]);
  const [volume, setVolume] = useState([1.0]);

  // Add console interceptor for debugging
  useEffect(() => {
    const originalLog = console.log;
    const originalError = console.error;

    console.log = (...args: any[]) => {
      originalLog(...args);
      const message = args.map(arg =>
        typeof arg === 'object' ? JSON.stringify(arg, null, 2) : String(arg)
      ).join(' ');
      if (message.includes('[TTS Adapter]')) {
        setLogs(prev => [...prev.slice(-19), `[${new Date().toLocaleTimeString()}] ${message}`]);
      }
    };

    console.error = (...args: any[]) => {
      originalError(...args);
      const message = args.map(arg =>
        typeof arg === 'object' ? JSON.stringify(arg, null, 2) : String(arg)
      ).join(' ');
      if (message.includes('[TTS Adapter]')) {
        setLogs(prev => [...prev.slice(-19), `[ERROR ${new Date().toLocaleTimeString()}] ${message}`]);
      }
    };

    return () => {
      console.log = originalLog;
      console.error = originalError;
    };
  }, []);

  const tts = useTTS({
    voice: selectedVoice || undefined,
    rate: rate[0],
    pitch: pitch[0],
    volume: volume[0],
    language: 'en-US',
    autoPlay: true
  });

  // Sample texts for quick testing
  const sampleTexts = [
    'Hello! This is a test of the Text-to-Speech system using the RunAnywhere SDK.',
    'The quick brown fox jumps over the lazy dog. This sentence contains every letter of the alphabet.',
    'Welcome to our advanced Text-to-Speech testing interface. Please enjoy testing the various voice options and settings.',
    'Testing numbers: One, two, three, four, five. Testing dates: January 1st, 2024. Testing time: 3:30 PM.',
    'This is a longer paragraph to test speech synthesis with extended content. The system should handle longer texts smoothly and maintain natural speech patterns throughout the entire passage.',
  ];

  const handleSpeak = async () => {
    if (!textInput.trim()) {
      alert('Please enter some text to speak');
      return;
    }
    await tts.speak(textInput);
  };

  const handleVoiceChange = (voiceName: string) => {
    setSelectedVoice(voiceName);
    tts.setVoice(voiceName);
  };

  const handleRateChange = (newRate: number[]) => {
    setRate(newRate);
    tts.setRate(newRate[0]);
  };

  const handlePitchChange = (newPitch: number[]) => {
    setPitch(newPitch);
    tts.setPitch(newPitch[0]);
  };

  const handleVolumeChange = (newVolume: number[]) => {
    setVolume(newVolume);
    tts.setVolume(newVolume[0]);
  };

  return (
    <div className="min-h-screen bg-background p-8">
      <div className="max-w-4xl mx-auto space-y-6">
        <div className="text-center space-y-2">
          <h1 className="text-4xl font-bold">Text-to-Speech Test</h1>
          <p className="text-muted-foreground">
            Testing Text-to-Speech with @runanywhere/tts
          </p>
        </div>

        {/* Status Card */}
        <Card>
          <CardHeader>
            <CardTitle>TTS Status</CardTitle>
            <CardDescription>
              Real-time text-to-speech status
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {/* Status Badges */}
            <div className="flex flex-wrap gap-2">
              <Badge variant={tts.isInitialized ? 'default' : 'secondary'}>
                {tts.isInitialized ? '✓ Initialized' : '○ Not Initialized'}
              </Badge>
              <Badge
                variant={tts.isSpeaking ? 'destructive' : 'secondary'}
                className={tts.isSpeaking ? 'animate-pulse' : ''}
              >
                {tts.isSpeaking ? '🔊 Speaking' : '○ Silent'}
              </Badge>
              <Badge variant={tts.availableVoices.length > 0 ? 'default' : 'secondary'}>
                {tts.availableVoices.length} Voices Available
              </Badge>
            </div>

            {/* Error Display */}
            {tts.error && (
              <div className="bg-destructive/10 border border-destructive/20 rounded-lg p-3 flex items-start gap-2">
                <AlertCircle className="w-5 h-5 text-destructive mt-0.5" />
                <div className="flex-1">
                  <p className="text-sm font-medium text-destructive">Error</p>
                  <p className="text-sm text-muted-foreground">{tts.error}</p>
                </div>
                <Button size="sm" variant="ghost" onClick={tts.clearError}>
                  Clear
                </Button>
              </div>
            )}

            {/* Last Synthesis Info */}
            {tts.lastSynthesis && (
              <div className="bg-primary/10 border border-primary/20 rounded-lg p-3">
                <p className="text-sm font-medium">Last Synthesis</p>
                <div className="text-sm text-muted-foreground space-y-1">
                  <p>Text: {tts.lastSynthesis.text.substring(0, 50)}...</p>
                  <p>Duration: {tts.lastSynthesis.duration.toFixed(2)}s</p>
                  <p>Processing Time: {tts.lastSynthesis.processingTime.toFixed(0)}ms</p>
                  <p>Voice: {tts.lastSynthesis.voice}</p>
                </div>
              </div>
            )}

            {/* Selected Voice Info */}
            {tts.selectedVoice && (
              <div className="bg-muted rounded-lg p-3">
                <p className="text-sm font-medium">Selected Voice</p>
                <div className="text-sm text-muted-foreground space-y-1">
                  <p>Name: {tts.selectedVoice.name}</p>
                  <p>Language: {tts.selectedVoice.language}</p>
                  <p>Quality: {tts.selectedVoice.quality}</p>
                  <p>Local: {tts.selectedVoice.isLocal ? 'Yes' : 'No'}</p>
                  {tts.selectedVoice.gender && <p>Gender: {tts.selectedVoice.gender}</p>}
                </div>
              </div>
            )}
          </CardContent>
        </Card>

        {/* Text Input Card */}
        <Card>
          <CardHeader>
            <CardTitle>Text Input</CardTitle>
            <CardDescription>
              Enter text to convert to speech
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {/* Text Area */}
            <div className="space-y-2">
              <Label htmlFor="text-input">Text to Speak</Label>
              <Textarea
                id="text-input"
                placeholder="Enter text here..."
                value={textInput}
                onChange={(e) => setTextInput(e.target.value)}
                rows={4}
              />
              <p className="text-sm text-muted-foreground">
                Character count: {textInput.length}
              </p>
            </div>

            {/* Sample Texts */}
            <div className="space-y-2">
              <Label>Quick Sample Texts</Label>
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-2">
                {sampleTexts.map((sample, index) => (
                  <Button
                    key={index}
                    variant="outline"
                    size="sm"
                    onClick={() => setTextInput(sample)}
                    className="h-auto p-2 text-left justify-start"
                  >
                    <span className="truncate">{sample.substring(0, 40)}...</span>
                  </Button>
                ))}
              </div>
            </div>

            {/* Main Controls */}
            <div className="flex flex-wrap gap-2">
              {!tts.isInitialized && (
                <Button
                  onClick={tts.initialize}
                  variant="outline"
                >
                  <Settings className="w-4 h-4 mr-2" />
                  Initialize TTS
                </Button>
              )}

              <Button
                onClick={handleSpeak}
                disabled={!textInput.trim() || tts.isSpeaking}
                variant="default"
              >
                <Volume2 className="w-4 h-4 mr-2" />
                Speak Text
              </Button>

              {tts.isSpeaking && (
                <>
                  <Button
                    onClick={tts.pause}
                    variant="outline"
                  >
                    <Pause className="w-4 h-4 mr-2" />
                    Pause
                  </Button>

                  <Button
                    onClick={tts.resume}
                    variant="outline"
                  >
                    <Play className="w-4 h-4 mr-2" />
                    Resume
                  </Button>

                  <Button
                    onClick={tts.stop}
                    variant="destructive"
                  >
                    <Square className="w-4 h-4 mr-2" />
                    Stop
                  </Button>
                </>
              )}
            </div>
          </CardContent>
        </Card>

        {/* Voice Settings Card */}
        <Card>
          <CardHeader>
            <CardTitle>Voice Settings</CardTitle>
            <CardDescription>
              Configure voice parameters
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-6">
            {/* Voice Selection */}
            {tts.availableVoices.length > 0 && (
              <div className="space-y-2">
                <Label>Voice</Label>
                <Select value={selectedVoice} onValueChange={handleVoiceChange}>
                  <SelectTrigger>
                    <SelectValue placeholder="Select a voice" />
                  </SelectTrigger>
                  <SelectContent>
                    {tts.availableVoices.map((voice) => (
                      <SelectItem key={voice.name} value={voice.name}>
                        {voice.name} ({voice.language})
                        {voice.isLocal && ' 🏠'}
                        {voice.isDefault && ' ⭐'}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            )}

            {/* Rate Control */}
            <div className="space-y-2">
              <Label>Speech Rate: {rate[0].toFixed(2)}x</Label>
              <Slider
                value={rate}
                onValueChange={handleRateChange}
                min={0.1}
                max={3.0}
                step={0.1}
                className="w-full"
              />
              <div className="flex justify-between text-xs text-muted-foreground">
                <span>Slow (0.1x)</span>
                <span>Normal (1.0x)</span>
                <span>Fast (3.0x)</span>
              </div>
            </div>

            {/* Pitch Control */}
            <div className="space-y-2">
              <Label>Pitch: {pitch[0].toFixed(2)}</Label>
              <Slider
                value={pitch}
                onValueChange={handlePitchChange}
                min={0.0}
                max={2.0}
                step={0.1}
                className="w-full"
              />
              <div className="flex justify-between text-xs text-muted-foreground">
                <span>Low (0.0)</span>
                <span>Normal (1.0)</span>
                <span>High (2.0)</span>
              </div>
            </div>

            {/* Volume Control */}
            <div className="space-y-2">
              <Label>Volume: {Math.round(volume[0] * 100)}%</Label>
              <Slider
                value={volume}
                onValueChange={handleVolumeChange}
                min={0.0}
                max={1.0}
                step={0.05}
                className="w-full"
              />
              <div className="flex justify-between text-xs text-muted-foreground">
                <span>Mute (0%)</span>
                <span>Half (50%)</span>
                <span>Full (100%)</span>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Instructions Card */}
        <Card>
          <CardHeader>
            <CardTitle>Instructions</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm text-muted-foreground">
            <p>1. Click "Initialize TTS" to set up the TTS adapter</p>
            <p>2. Enter text in the text area or select a sample text</p>
            <p>3. Optionally configure voice settings (voice, rate, pitch, volume)</p>
            <p>4. Click "Speak Text" to convert text to speech</p>
            <p>5. Use pause/resume/stop controls during playback</p>
            <p>6. Check the browser console for detailed logs</p>
          </CardContent>
        </Card>

        {/* Technical Info */}
        <Card>
          <CardHeader>
            <CardTitle>Technical Details</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm font-mono text-muted-foreground">
            <p>Package: @runanywhere/tts</p>
            <p>Engine: Web Speech API</p>
            <p>Auto-play: Enabled</p>
            <p>Rate Range: 0.1x - 3.0x</p>
            <p>Pitch Range: 0.0 - 2.0</p>
            <p>Volume Range: 0% - 100%</p>
          </CardContent>
        </Card>

        {/* Debug Logs */}
        <Card>
          <CardHeader>
            <CardTitle>Debug Logs</CardTitle>
            <CardDescription>
              Real-time TTS logs (last 20 entries)
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
