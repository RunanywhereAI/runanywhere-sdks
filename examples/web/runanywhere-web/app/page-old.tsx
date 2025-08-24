'use client';

import { useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Badge } from '@/components/ui/badge';
import { Slider } from '@/components/ui/slider';
import { Switch } from '@/components/ui/switch';
import {
  Mic, MicOff, Settings, Volume2, Zap, Brain, Shield, DollarSign,
  AlertCircle, Download, Play, Pause, FileAudio, MessageSquare, Sparkles,
  Sun, Moon
} from 'lucide-react';
import { useVoiceAssistant } from '@/hooks/useVoiceAssistant';

export default function Home() {
  const [apiKey, setApiKey] = useState('');
  const [volume, setVolume] = useState([0.7]);
  const [speed, setSpeed] = useState([1.0]);
  const [useLocalModels, setUseLocalModels] = useState(true);
  const [ttsText, setTtsText] = useState('');
  const [isSpeaking, setIsSpeaking] = useState(false);
  const [llmMessage, setLlmMessage] = useState('');
  const [llmResponse, setLlmResponse] = useState('');
  const [isDarkMode, setIsDarkMode] = useState(false);
  const [downloadStatus, setDownloadStatus] = useState({
    vad: false,
    stt: false,
    tts: false,
    llm: false
  });

  // Use the voice assistant hook
  const {
    isListening,
    isProcessing,
    transcript,
    response,
    error,
    toggleListening,
  } = useVoiceAssistant({
    apiKey,
    useLocalModels,
    volume: volume[0],
    speed: speed[0],
  });

  useEffect(() => {
    // Check if API key exists in localStorage
    const savedKey = localStorage.getItem('openai_api_key');
    if (savedKey) {
      setApiKey(savedKey);
    }

    // Check dark mode preference
    if (window.matchMedia('(prefers-color-scheme: dark)').matches) {
      setIsDarkMode(true);
      document.documentElement.classList.add('dark');
    }
  }, []);

  const toggleDarkMode = () => {
    setIsDarkMode(!isDarkMode);
    document.documentElement.classList.toggle('dark');
  };

  const handleSaveApiKey = () => {
    if (apiKey.trim()) {
      localStorage.setItem('openai_api_key', apiKey);
    }
  };

  const handleDownloadModel = (modelType: string) => {
    // Simulate model download
    setDownloadStatus(prev => ({ ...prev, [modelType]: true }));
    setTimeout(() => {
      alert(`${modelType.toUpperCase()} model downloaded successfully!`);
    }, 1000);
  };

  const handleTTS = () => {
    if (!ttsText.trim()) return;

    setIsSpeaking(true);
    const utterance = new SpeechSynthesisUtterance(ttsText);
    utterance.volume = volume[0];
    utterance.rate = speed[0];
    utterance.onend = () => setIsSpeaking(false);
    window.speechSynthesis.speak(utterance);
  };

  const stopTTS = () => {
    window.speechSynthesis.cancel();
    setIsSpeaking(false);
  };

  const handleLLMSubmit = async () => {
    if (!llmMessage.trim() || !apiKey) return;

    setLlmResponse('Processing...');

    try {
      const response = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
          model: 'gpt-4-turbo-preview',
          messages: [
            { role: 'system', content: 'You are a helpful assistant. Keep responses concise.' },
            { role: 'user', content: llmMessage }
          ],
          temperature: 0.7,
          max_tokens: 150,
        }),
      });

      if (!response.ok) {
        throw new Error('Failed to get AI response');
      }

      const data = await response.json();
      setLlmResponse(data.choices[0].message.content);
    } catch (err) {
      setLlmResponse('Error: Failed to get response. Please check your API key.');
    }
  };

  return (
    <div className="min-h-screen bg-background">
      <div className="container max-w-7xl mx-auto px-4 py-6">
        {/* Header */}
        <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-8">
          <div className="flex items-center gap-3">
            <div className="p-2.5 bg-primary rounded-xl shadow-lg">
              <Brain className="h-6 w-6 text-primary-foreground" />
            </div>
            <div>
              <h1 className="text-2xl sm:text-3xl font-bold text-foreground">
                RunAnywhere AI
              </h1>
              <p className="text-sm text-muted-foreground">Modular AI Pipeline Testing</p>
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-3">
            <Button
              variant="outline"
              size="icon"
              onClick={toggleDarkMode}
              className="border-border"
            >
              {isDarkMode ? <Sun className="h-4 w-4" /> : <Moon className="h-4 w-4" />}
            </Button>
            <Badge
              variant={useLocalModels ? "default" : "secondary"}
              className="px-3 py-1"
            >
              {useLocalModels ? (
                <>
                  <span className="inline-block w-2 h-2 bg-green-500 rounded-full mr-2 animate-pulse"></span>
                  On-Device
                </>
              ) : (
                <>
                  <span className="inline-block w-2 h-2 bg-blue-500 rounded-full mr-2"></span>
                  Cloud
                </>
              )}
            </Badge>
            <div className="flex items-center gap-2">
              <Input
                type="password"
                placeholder="OpenAI API Key (optional)"
                value={apiKey}
                onChange={(e) => setApiKey(e.target.value)}
                className="w-48 sm:w-64 bg-background border-input"
              />
              <Button onClick={handleSaveApiKey} size="sm" className="bg-primary text-primary-foreground hover:bg-primary/90">
                Save
              </Button>
            </div>
          </div>
        </div>

        {/* Main Content with Tabs */}
        <Tabs defaultValue="pipeline" className="w-full">
          <TabsList className="grid w-full grid-cols-2 sm:grid-cols-4 mb-6 bg-muted">
            <TabsTrigger value="pipeline" className="flex items-center gap-1 sm:gap-2 text-xs sm:text-sm">
              <Sparkles className="h-3 w-3 sm:h-4 sm:w-4" />
              <span className="hidden sm:inline">Full Pipeline</span>
              <span className="sm:hidden">Pipeline</span>
            </TabsTrigger>
            <TabsTrigger value="stt" className="flex items-center gap-1 sm:gap-2 text-xs sm:text-sm">
              <Mic className="h-3 w-3 sm:h-4 sm:w-4" />
              <span className="hidden sm:inline">Speech to Text</span>
              <span className="sm:hidden">STT</span>
            </TabsTrigger>
            <TabsTrigger value="tts" className="flex items-center gap-1 sm:gap-2 text-xs sm:text-sm">
              <Volume2 className="h-3 w-3 sm:h-4 sm:w-4" />
              <span className="hidden sm:inline">Text to Speech</span>
              <span className="sm:hidden">TTS</span>
            </TabsTrigger>
            <TabsTrigger value="llm" className="flex items-center gap-1 sm:gap-2 text-xs sm:text-sm">
              <MessageSquare className="h-3 w-3 sm:h-4 sm:w-4" />
              <span className="hidden sm:inline">LLM Chat</span>
              <span className="sm:hidden">LLM</span>
            </TabsTrigger>
          </TabsList>

          {/* Full Pipeline Tab */}
          <TabsContent value="pipeline" className="space-y-6">
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
              <div className="lg:col-span-2">
                <Card className="border-border bg-card">
                  <CardHeader>
                    <CardTitle className="text-xl text-card-foreground">Complete Voice Pipeline</CardTitle>
                    <CardDescription className="text-muted-foreground">VAD → STT → LLM → TTS</CardDescription>
                    {!apiKey && (
                      <div className="mt-2 p-3 bg-yellow-500/10 rounded-lg border border-yellow-500/20">
                        <p className="text-sm text-yellow-600 dark:text-yellow-400">
                          ⚠️ Add OpenAI API key above to enable LLM responses
                        </p>
                      </div>
                    )}
                  </CardHeader>
                  <CardContent className="space-y-6">
                    <div className="flex justify-center py-8 relative">
                      {isListening && (
                        <div className="absolute inset-0 flex items-center justify-center">
                          <div className="h-40 w-40 bg-primary/20 rounded-full animate-ping"></div>
                        </div>
                      )}
                      <Button
                        size="lg"
                        className={`h-28 w-28 sm:h-32 sm:w-32 rounded-full transition-all transform hover:scale-105 relative z-10 ${
                          isListening
                            ? 'bg-destructive hover:bg-destructive/90'
                            : 'bg-primary hover:bg-primary/90'
                        }`}
                        onClick={toggleListening}
                      >
                        {isListening ? (
                          <MicOff className="h-10 w-10 sm:h-12 sm:w-12 text-primary-foreground" />
                        ) : (
                          <Mic className="h-10 w-10 sm:h-12 sm:w-12 text-primary-foreground" />
                        )}
                      </Button>
                    </div>

                    {error && (
                      <div className="p-3 bg-destructive/10 rounded-lg border border-destructive/20">
                        <p className="text-sm text-destructive">{error}</p>
                      </div>
                    )}

                    {transcript && (
                      <div className="space-y-2">
                        <Label className="text-card-foreground">Transcript:</Label>
                        <div className="p-4 bg-muted rounded-lg">
                          <p className="text-card-foreground">{transcript}</p>
                        </div>
                      </div>
                    )}

                    {response && (
                      <div className="space-y-2">
                        <Label className="text-card-foreground">AI Response:</Label>
                        <div className="p-4 bg-primary/10 rounded-lg">
                          <p className="text-card-foreground">{response}</p>
                        </div>
                      </div>
                    )}
                  </CardContent>
                </Card>
              </div>

              <div className="space-y-6">
                <Card className="border-border bg-card">
                  <CardHeader>
                    <CardTitle className="text-lg text-card-foreground">Pipeline Status</CardTitle>
                  </CardHeader>
                  <CardContent className="space-y-3">
                    <div className="flex items-center justify-between">
                      <span className="text-sm text-muted-foreground">VAD (Voice Activity)</span>
                      <Badge variant={downloadStatus.vad ? "default" : "secondary"}>
                        {downloadStatus.vad ? "Ready" : "Not Loaded"}
                      </Badge>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="text-sm text-muted-foreground">STT (Whisper)</span>
                      <Badge variant={downloadStatus.stt ? "default" : "secondary"}>
                        {downloadStatus.stt ? "Ready" : "Not Loaded"}
                      </Badge>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="text-sm text-muted-foreground">LLM (OpenAI)</span>
                      <Badge variant={apiKey ? "default" : "secondary"}>
                        {apiKey ? "Configured" : "API Key Required"}
                      </Badge>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="text-sm text-muted-foreground">TTS (Web Speech)</span>
                      <Badge variant="default">Ready</Badge>
                    </div>
                  </CardContent>
                </Card>

                <Card className="border-border bg-card">
                  <CardHeader>
                    <CardTitle className="text-lg text-card-foreground">Model Downloads</CardTitle>
                  </CardHeader>
                  <CardContent className="space-y-3">
                    <Button
                      onClick={() => handleDownloadModel('vad')}
                      disabled={downloadStatus.vad}
                      className="w-full"
                      variant="outline"
                    >
                      <Download className="h-4 w-4 mr-2" />
                      {downloadStatus.vad ? "VAD Model Ready" : "Download VAD Model"}
                    </Button>
                    <Button
                      onClick={() => handleDownloadModel('stt')}
                      disabled={downloadStatus.stt}
                      className="w-full"
                      variant="outline"
                    >
                      <Download className="h-4 w-4 mr-2" />
                      {downloadStatus.stt ? "STT Model Ready" : "Download Whisper Model"}
                    </Button>
                  </CardContent>
                </Card>
              </div>
            </div>
          </TabsContent>

          {/* Speech to Text Tab */}
          <TabsContent value="stt" className="space-y-6">
            <Card className="max-w-3xl mx-auto border-border bg-card">
              <CardHeader>
                <CardTitle className="text-card-foreground">Speech to Text Testing</CardTitle>
                <CardDescription className="text-muted-foreground">Test VAD + STT independently</CardDescription>
              </CardHeader>
              <CardContent className="space-y-6">
                <div className="grid grid-cols-2 gap-4">
                  <Button
                    onClick={() => handleDownloadModel('vad')}
                    disabled={downloadStatus.vad}
                    variant="outline"
                  >
                    <Download className="h-4 w-4 mr-2" />
                    {downloadStatus.vad ? "VAD Ready" : "Download VAD"}
                  </Button>
                  <Button
                    onClick={() => handleDownloadModel('stt')}
                    disabled={downloadStatus.stt}
                    variant="outline"
                  >
                    <Download className="h-4 w-4 mr-2" />
                    {downloadStatus.stt ? "Whisper Ready" : "Download Whisper"}
                  </Button>
                </div>

                <div className="flex justify-center py-8">
                  <Button
                    size="lg"
                    className={`h-24 w-24 rounded-full ${
                      isListening
                        ? 'bg-destructive hover:bg-destructive/90'
                        : 'bg-primary hover:bg-primary/90'
                    }`}
                    onClick={toggleListening}
                  >
                    {isListening ? (
                      <MicOff className="h-8 w-8 text-primary-foreground" />
                    ) : (
                      <Mic className="h-8 w-8 text-primary-foreground" />
                    )}
                  </Button>
                </div>

                {transcript && (
                  <div className="space-y-2">
                    <Label className="text-card-foreground">Transcribed Text:</Label>
                    <div className="p-6 bg-muted rounded-lg border border-border">
                      <p className="text-lg text-card-foreground">{transcript}</p>
                    </div>
                  </div>
                )}

                <div className="grid grid-cols-3 gap-4 pt-4">
                  <div className="text-center p-3 bg-muted rounded-lg">
                    <p className="text-xs text-muted-foreground">Model</p>
                    <p className="font-medium text-card-foreground">Whisper Tiny</p>
                  </div>
                  <div className="text-center p-3 bg-muted rounded-lg">
                    <p className="text-xs text-muted-foreground">Language</p>
                    <p className="font-medium text-card-foreground">English</p>
                  </div>
                  <div className="text-center p-3 bg-muted rounded-lg">
                    <p className="text-xs text-muted-foreground">Latency</p>
                    <p className="font-medium text-card-foreground">~200ms</p>
                  </div>
                </div>
              </CardContent>
            </Card>
          </TabsContent>

          {/* Text to Speech Tab */}
          <TabsContent value="tts" className="space-y-6">
            <Card className="max-w-3xl mx-auto border-border bg-card">
              <CardHeader>
                <CardTitle className="text-card-foreground">Text to Speech Testing</CardTitle>
                <CardDescription className="text-muted-foreground">Test TTS models independently</CardDescription>
              </CardHeader>
              <CardContent className="space-y-6">
                <div className="space-y-2">
                  <Label className="text-card-foreground">Enter text to speak:</Label>
                  <textarea
                    className="w-full p-4 border border-input rounded-lg resize-none bg-background text-foreground"
                    rows={4}
                    placeholder="Type something here..."
                    value={ttsText}
                    onChange={(e) => setTtsText(e.target.value)}
                  />
                </div>

                <div className="flex gap-4">
                  <Button
                    onClick={handleTTS}
                    disabled={!ttsText.trim() || isSpeaking}
                    className="flex-1 bg-primary text-primary-foreground hover:bg-primary/90"
                  >
                    <Play className="h-4 w-4 mr-2" />
                    Speak Text
                  </Button>
                  <Button
                    onClick={stopTTS}
                    disabled={!isSpeaking}
                    variant="outline"
                  >
                    <Pause className="h-4 w-4 mr-2" />
                    Stop
                  </Button>
                </div>

                <div className="space-y-4 pt-4 border-t border-border">
                  <div className="space-y-3">
                    <div className="flex items-center gap-2">
                      <Volume2 className="h-5 w-5 text-primary" />
                      <Label className="text-card-foreground">Volume</Label>
                    </div>
                    <div className="flex items-center gap-3">
                      <Slider
                        value={volume}
                        onValueChange={setVolume}
                        max={1}
                        step={0.1}
                        className="flex-1"
                      />
                      <span className="text-sm font-medium w-12 text-card-foreground">{Math.round(volume[0] * 100)}%</span>
                    </div>
                  </div>

                  <div className="space-y-3">
                    <div className="flex items-center gap-2">
                      <Zap className="h-5 w-5 text-primary" />
                      <Label className="text-card-foreground">Speed</Label>
                    </div>
                    <div className="flex items-center gap-3">
                      <Slider
                        value={speed}
                        onValueChange={setSpeed}
                        min={0.5}
                        max={2}
                        step={0.1}
                        className="flex-1"
                      />
                      <span className="text-sm font-medium w-12 text-card-foreground">{speed[0].toFixed(1)}x</span>
                    </div>
                  </div>
                </div>

                <div className="grid grid-cols-3 gap-4 pt-4">
                  <div className="text-center p-3 bg-muted rounded-lg">
                    <p className="text-xs text-muted-foreground">Engine</p>
                    <p className="font-medium text-card-foreground">Web Speech</p>
                  </div>
                  <div className="text-center p-3 bg-muted rounded-lg">
                    <p className="text-xs text-muted-foreground">Voice</p>
                    <p className="font-medium text-card-foreground">System</p>
                  </div>
                  <div className="text-center p-3 bg-muted rounded-lg">
                    <p className="text-xs text-muted-foreground">Quality</p>
                    <p className="font-medium text-card-foreground">High</p>
                  </div>
                </div>
              </CardContent>
            </Card>
          </TabsContent>

          {/* LLM Chat Tab */}
          <TabsContent value="llm" className="space-y-6">
            <Card className="max-w-3xl mx-auto border-border bg-card">
              <CardHeader>
                <CardTitle className="text-card-foreground">LLM Chat Testing</CardTitle>
                <CardDescription className="text-muted-foreground">Test language model independently</CardDescription>
                {!apiKey && (
                  <div className="mt-2 p-3 bg-yellow-500/10 rounded-lg border border-yellow-500/20">
                    <p className="text-sm text-yellow-600 dark:text-yellow-400">
                      ⚠️ Add your OpenAI API key at the top to enable this feature
                    </p>
                  </div>
                )}
              </CardHeader>
              <CardContent className="space-y-6">
                <div className="space-y-2">
                  <Label className="text-card-foreground">Enter your message:</Label>
                  <textarea
                    className="w-full p-4 border border-input rounded-lg resize-none bg-background text-foreground"
                    rows={3}
                    placeholder="Ask anything..."
                    disabled={!apiKey}
                    value={llmMessage}
                    onChange={(e) => setLlmMessage(e.target.value)}
                  />
                </div>

                <Button
                  disabled={!apiKey || !llmMessage.trim()}
                  className="w-full bg-primary text-primary-foreground hover:bg-primary/90"
                  onClick={handleLLMSubmit}
                >
                  <MessageSquare className="h-4 w-4 mr-2" />
                  Send Message
                </Button>

                <div className="space-y-2">
                  <Label className="text-card-foreground">Response:</Label>
                  <div className="min-h-[100px] p-4 bg-muted rounded-lg border border-border">
                    <p className="text-card-foreground">
                      {llmResponse || (apiKey ? "Response will appear here..." : "API key required")}
                    </p>
                  </div>
                </div>

                <div className="grid grid-cols-3 gap-4 pt-4">
                  <div className="text-center p-3 bg-muted rounded-lg">
                    <p className="text-xs text-muted-foreground">Model</p>
                    <p className="font-medium text-card-foreground">GPT-4</p>
                  </div>
                  <div className="text-center p-3 bg-muted rounded-lg">
                    <p className="text-xs text-muted-foreground">Tokens</p>
                    <p className="font-medium text-card-foreground">0</p>
                  </div>
                  <div className="text-center p-3 bg-muted rounded-lg">
                    <p className="text-xs text-muted-foreground">Cost</p>
                    <p className="font-medium text-card-foreground">$0.00</p>
                  </div>
                </div>
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>
      </div>
    </div>
  );
}
