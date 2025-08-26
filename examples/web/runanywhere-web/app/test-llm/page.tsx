'use client';

import { useLLMAdapter } from '@/hooks/useLLM';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { MessageSquare, Send, Trash2, AlertCircle, Activity, Bot, User, Zap, Clock, DollarSign } from 'lucide-react';
import { useEffect, useState } from 'react';

export default function TestLLMPage() {
  const [logs, setLogs] = useState<string[]>([]);
  const [apiKey, setApiKey] = useState('');
  const [message, setMessage] = useState('');
  const [systemPrompt, setSystemPrompt] = useState('You are a helpful assistant. Keep responses concise.');
  const [model, setModel] = useState('gpt-4o-mini');
  const [temperature, setTemperature] = useState(0.7);
  const [maxTokens, setMaxTokens] = useState(1000);
  const [isStreaming, setIsStreaming] = useState(false);

  // Add console interceptor for debugging
  useEffect(() => {
    const originalLog = console.log;
    const originalError = console.error;

    console.log = (...args: any[]) => {
      originalLog(...args);
      const message = args.map(arg =>
        typeof arg === 'object' ? JSON.stringify(arg, null, 2) : String(arg)
      ).join(' ');
      if (message.includes('[LLM Adapter]')) {
        setLogs(prev => [...prev.slice(-19), `[${new Date().toLocaleTimeString()}] ${message}`]);
      }
    };

    console.error = (...args: any[]) => {
      originalError(...args);
      const message = args.map(arg =>
        typeof arg === 'object' ? JSON.stringify(arg, null, 2) : String(arg)
      ).join(' ');
      if (message.includes('[LLM Adapter]')) {
        setLogs(prev => [...prev.slice(-19), `[ERROR ${new Date().toLocaleTimeString()}] ${message}`]);
      }
    };

    return () => {
      console.log = originalLog;
      console.error = originalError;
    };
  }, []);

  const llm = useLLMAdapter({
    defaultModel: model,
    systemPrompt,
  });

  const handleInitialize = async () => {
    if (!apiKey.trim()) {
      alert('Please enter an OpenAI API key');
      return;
    }
    await llm.initialize(apiKey);
  };

  const handleSendMessage = async () => {
    if (!message.trim()) return;

    const currentMessage = message;
    setMessage('');

    if (isStreaming) {
      const stream = llm.sendMessageStream(currentMessage, {
        model,
        temperature,
        maxTokens,
      });

      for await (const token of stream) {
        // Stream is handled by the hook's state updates
      }
    } else {
      await llm.sendMessage(currentMessage, {
        model,
        temperature,
        maxTokens,
      });
    }
  };

  const handleUpdateSystemPrompt = () => {
    llm.setSystemPrompt(systemPrompt);
  };

  return (
    <div className="min-h-screen bg-background p-8">
      <div className="max-w-6xl mx-auto space-y-6">
        <div className="text-center space-y-2">
          <h1 className="text-4xl font-bold">OpenAI LLM Test</h1>
          <p className="text-muted-foreground">
            Testing Large Language Model with @runanywhere/llm-openai
          </p>
        </div>

        {/* Configuration Card */}
        <Card>
          <CardHeader>
            <CardTitle>Configuration</CardTitle>
            <CardDescription>
              Configure your OpenAI LLM settings
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {/* API Key Input */}
            <div className="space-y-2">
              <Label htmlFor="apiKey">OpenAI API Key</Label>
              <div className="flex gap-2">
                <Input
                  id="apiKey"
                  type="password"
                  placeholder="sk-..."
                  value={apiKey}
                  onChange={(e) => setApiKey(e.target.value)}
                  className="flex-1"
                />
                <Button
                  onClick={handleInitialize}
                  disabled={llm.isInitialized || !apiKey.trim()}
                  variant="default"
                >
                  Initialize LLM
                </Button>
              </div>
            </div>

            {/* Model Selection */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div className="space-y-2">
                <Label htmlFor="model">Model</Label>
                <Select value={model} onValueChange={setModel}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="gpt-4o-mini">GPT-4o Mini</SelectItem>
                    <SelectItem value="gpt-4o">GPT-4o</SelectItem>
                    <SelectItem value="gpt-4-turbo">GPT-4 Turbo</SelectItem>
                    <SelectItem value="gpt-4">GPT-4</SelectItem>
                    <SelectItem value="gpt-3.5-turbo">GPT-3.5 Turbo</SelectItem>
                  </SelectContent>
                </Select>
              </div>

              <div className="space-y-2">
                <Label htmlFor="temperature">Temperature: {temperature}</Label>
                <Input
                  id="temperature"
                  type="range"
                  min="0"
                  max="2"
                  step="0.1"
                  value={temperature}
                  onChange={(e) => setTemperature(parseFloat(e.target.value))}
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="maxTokens">Max Tokens: {maxTokens}</Label>
                <Input
                  id="maxTokens"
                  type="range"
                  min="50"
                  max="4000"
                  step="50"
                  value={maxTokens}
                  onChange={(e) => setMaxTokens(parseInt(e.target.value))}
                />
              </div>
            </div>

            {/* System Prompt */}
            <div className="space-y-2">
              <Label htmlFor="systemPrompt">System Prompt</Label>
              <div className="flex gap-2">
                <Textarea
                  id="systemPrompt"
                  placeholder="You are a helpful assistant..."
                  value={systemPrompt}
                  onChange={(e) => setSystemPrompt(e.target.value)}
                  className="flex-1"
                  rows={3}
                />
                <Button
                  onClick={handleUpdateSystemPrompt}
                  disabled={!llm.isInitialized}
                  variant="outline"
                  size="sm"
                >
                  Update
                </Button>
              </div>
            </div>

            {/* Streaming Toggle */}
            <div className="flex items-center space-x-2">
              <input
                type="checkbox"
                id="streaming"
                checked={isStreaming}
                onChange={(e) => setIsStreaming(e.target.checked)}
                className="rounded"
              />
              <Label htmlFor="streaming">Enable Streaming</Label>
            </div>
          </CardContent>
        </Card>

        {/* Status Card */}
        <Card>
          <CardHeader>
            <CardTitle>LLM Status</CardTitle>
            <CardDescription>
              Real-time LLM adapter status and metrics
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {/* Status Badges */}
            <div className="flex flex-wrap gap-2">
              <Badge variant={llm.isInitialized ? 'default' : 'secondary'}>
                {llm.isInitialized ? '✓ Initialized' : '○ Not Initialized'}
              </Badge>
              <Badge variant={llm.isProcessing ? 'destructive' : 'secondary'}>
                {llm.isProcessing ? '🔄 Processing' : '○ Idle'}
              </Badge>
              <Badge variant={llm.isHealthy() ? 'default' : 'secondary'}>
                {llm.isHealthy() ? '✓ Healthy' : '○ Not Healthy'}
              </Badge>
            </div>

            {/* Error Display */}
            {llm.error && (
              <div className="bg-destructive/10 border border-destructive/20 rounded-lg p-3 flex items-start gap-2">
                <AlertCircle className="w-5 h-5 text-destructive mt-0.5" />
                <div className="flex-1">
                  <p className="text-sm font-medium text-destructive">Error</p>
                  <p className="text-sm text-muted-foreground">{llm.error}</p>
                </div>
              </div>
            )}

            {/* Last Completion Results */}
            {llm.lastCompletionResult && (
              <div className="bg-primary/10 border border-primary/20 rounded-lg p-3">
                <p className="text-sm font-medium">Last Completion</p>
                <div className="grid grid-cols-1 md:grid-cols-4 gap-2 mt-2 text-xs text-muted-foreground">
                  <div className="flex items-center gap-1">
                    <Clock className="w-3 h-3" />
                    {llm.lastCompletionResult.latency}ms
                  </div>
                  <div className="flex items-center gap-1">
                    <MessageSquare className="w-3 h-3" />
                    {llm.lastCompletionResult.usage?.totalTokens} tokens
                  </div>
                  <div className="flex items-center gap-1">
                    <Zap className="w-3 h-3" />
                    {llm.lastCompletionResult.finishReason}
                  </div>
                  <div className="text-xs">
                    {llm.lastCompletionResult.usage?.promptTokens}→{llm.lastCompletionResult.usage?.completionTokens}
                  </div>
                </div>
              </div>
            )}

            {/* Metrics Display */}
            {llm.isInitialized && (
              <div className="space-y-2">
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => {
                    const metrics = llm.getMetrics();
                    if (metrics) {
                      console.log('[LLM Metrics]', metrics);
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

        {/* Chat Interface */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Input Section */}
          <Card>
            <CardHeader>
              <CardTitle>Send Message</CardTitle>
              <CardDescription>
                Test LLM completion with your messages
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <Textarea
                placeholder="Enter your message here..."
                value={message}
                onChange={(e) => setMessage(e.target.value)}
                rows={6}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' && e.ctrlKey) {
                    handleSendMessage();
                  }
                }}
              />
              <div className="flex gap-2">
                <Button
                  onClick={handleSendMessage}
                  disabled={!llm.isInitialized || llm.isProcessing || !message.trim()}
                  className="flex-1"
                >
                  <Send className="w-4 h-4 mr-2" />
                  Send Message (Ctrl+Enter)
                </Button>
                <Button
                  onClick={llm.clearHistory}
                  disabled={!llm.isInitialized || llm.conversationHistory.length === 0}
                  variant="outline"
                >
                  <Trash2 className="w-4 h-4 mr-2" />
                  Clear History
                </Button>
              </div>
            </CardContent>
          </Card>

          {/* Response Section */}
          <Card>
            <CardHeader>
              <CardTitle>Latest Response</CardTitle>
              <CardDescription>
                {isStreaming ? 'Streaming response (real-time)' : 'Complete response'}
              </CardDescription>
            </CardHeader>
            <CardContent>
              <div className="bg-muted rounded-lg p-4 min-h-[150px] max-h-[300px] overflow-y-auto">
                {llm.response ? (
                  <div className="whitespace-pre-wrap text-sm">
                    {llm.response}
                    {llm.isProcessing && isStreaming && (
                      <span className="animate-pulse">▋</span>
                    )}
                  </div>
                ) : (
                  <p className="text-sm text-muted-foreground">No response yet...</p>
                )}
              </div>
            </CardContent>
          </Card>
        </div>

        {/* Conversation History */}
        <Card>
          <CardHeader>
            <CardTitle>Conversation History</CardTitle>
            <CardDescription>
              Complete conversation with the LLM ({llm.conversationHistory.length} messages)
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="bg-muted rounded-lg p-4 max-h-[400px] overflow-y-auto">
              {llm.conversationHistory.length === 0 ? (
                <p className="text-sm text-muted-foreground">No conversation yet...</p>
              ) : (
                <div className="space-y-3">
                  {llm.conversationHistory.map((msg, i) => (
                    <div
                      key={i}
                      className={`flex items-start gap-2 ${
                        msg.role === 'user' ? 'flex-row-reverse' : 'flex-row'
                      }`}
                    >
                      <div
                        className={`p-2 rounded-lg max-w-[80%] ${
                          msg.role === 'user'
                            ? 'bg-primary text-primary-foreground'
                            : 'bg-background border'
                        }`}
                      >
                        <div className="flex items-center gap-1 mb-1">
                          {msg.role === 'user' ? (
                            <User className="w-3 h-3" />
                          ) : (
                            <Bot className="w-3 h-3" />
                          )}
                          <span className="text-xs font-medium capitalize">
                            {msg.role}
                          </span>
                        </div>
                        <div className="text-sm whitespace-pre-wrap">
                          {msg.content}
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </CardContent>
        </Card>

        {/* Instructions and Technical Info */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          {/* Instructions Card */}
          <Card>
            <CardHeader>
              <CardTitle>Instructions</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2 text-sm text-muted-foreground">
              <p>1. Enter your OpenAI API key (starts with &quot;sk-&quot;)</p>
              <p>2. Click &quot;Initialize LLM&quot; to set up the OpenAI adapter</p>
              <p>3. Configure model, temperature, and other settings</p>
              <p>4. Update system prompt if needed</p>
              <p>5. Type your message and click &quot;Send&quot; or use Ctrl+Enter</p>
              <p>6. Enable streaming for real-time token-by-token responses</p>
              <p>7. View conversation history and metrics</p>
              <p>8. Check browser console for detailed logs</p>
            </CardContent>
          </Card>

          {/* Technical Info */}
          <Card>
            <CardHeader>
              <CardTitle>Technical Details</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2 text-sm font-mono text-muted-foreground">
              <p>Package: @runanywhere/llm-openai</p>
              <p>Provider: OpenAI</p>
              <p>Current Model: {model}</p>
              <p>Temperature: {temperature}</p>
              <p>Max Tokens: {maxTokens}</p>
              <p>Streaming: {isStreaming ? 'Enabled' : 'Disabled'}</p>
              <p>History Tracking: Enabled</p>
              <p>Cost Calculation: Enabled</p>
            </CardContent>
          </Card>
        </div>

        {/* Debug Logs */}
        <Card>
          <CardHeader>
            <CardTitle>Debug Logs</CardTitle>
            <CardDescription>
              Real-time LLM adapter logs (last 20 entries)
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
