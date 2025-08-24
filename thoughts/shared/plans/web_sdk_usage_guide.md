# RunAnywhere Web Voice SDK - Developer Consumption Guide

A comprehensive guide for developers to integrate and use the RunAnywhere Web Voice SDK for building voice-powered applications with real-time speech processing capabilities.

## Table of Contents

1. [Getting Started](#getting-started)
2. [Quick Start Examples](#quick-start-examples)
3. [Framework-Specific Integration](#framework-specific-integration)
4. [Configuration Guide](#configuration-guide)
5. [Advanced Usage Patterns](#advanced-usage-patterns)
6. [API Reference](#api-reference)
7. [Common Use Cases](#common-use-cases)
8. [Troubleshooting and Best Practices](#troubleshooting-and-best-practices)

## Getting Started

### Installation

The RunAnywhere Web Voice SDK is distributed as a monorepo with framework-specific packages. Choose the appropriate package for your framework:

```bash
# For React applications
npm install @runanywhere/react @runanywhere/core @runanywhere/voice

# For Vue.js applications
npm install @runanywhere/vue @runanywhere/core @runanywhere/voice

# For Angular applications
npm install @runanywhere/angular @runanywhere/core @runanywhere/voice

# For vanilla JavaScript
npm install @runanywhere/core @runanywhere/voice
```

### Required Dependencies

The SDK requires these peer dependencies:

```bash
# Additional service packages (optional but recommended)
npm install @runanywhere/transcription @runanywhere/llm @runanywhere/tts @runanywhere/cache @runanywhere/monitoring

# For React
npm install react react-dom

# For Vue
npm install vue

# For Angular
npm install @angular/core @angular/common rxjs
```

### Browser Support

- **Modern browsers** with WebRTC, Web Audio API, and MediaDevices support
- **Chrome**: 88+
- **Firefox**: 84+
- **Safari**: 14.1+
- **Edge**: 88+

### Basic Setup

1. **Obtain API credentials** (OpenAI API key for LLM services)
2. **Configure your build system** to handle Web Workers and WASM modules
3. **Set up HTTPS** (required for microphone access)

## Quick Start Examples

### Simple Voice Pipeline Setup

```typescript
import { useVoicePipeline } from '@runanywhere/react';

function VoiceApp() {
  const [state, actions] = useVoicePipeline({
    enableTranscription: true,
    enableLLM: true,
    enableTTS: true,
    llmConfig: {
      apiKey: process.env.REACT_APP_OPENAI_API_KEY,
      model: 'gpt-3.5-turbo',
      temperature: 0.7
    },
    whisperConfig: {
      model: 'whisper-base'
    },
    ttsConfig: {
      voice: 'jenny',
      rate: 1.0
    }
  });

  const handleStart = async () => {
    if (!state.isInitialized) {
      await actions.initialize();
    }
    await actions.start();
  };

  return (
    <div>
      <button onClick={handleStart} disabled={state.isProcessing}>
        {state.isListening ? 'Stop Listening' : 'Start Voice Chat'}
      </button>

      {state.transcription && (
        <p>You said: {state.transcription}</p>
      )}

      {state.llmResponse && (
        <p>Assistant: {state.llmResponse}</p>
      )}

      {state.error && (
        <p>Error: {state.error.message}</p>
      )}
    </div>
  );
}
```

### Basic React Integration Example

```typescript
import React from 'react';
import { useVoicePipeline, UseVoicePipelineOptions } from '@runanywhere/react';

interface VoiceAssistantProps {
  apiKey: string;
  onTranscription?: (text: string) => void;
  onResponse?: (text: string) => void;
}

export function VoiceAssistant({
  apiKey,
  onTranscription,
  onResponse
}: VoiceAssistantProps) {
  const options: UseVoicePipelineOptions = {
    enableTranscription: true,
    enableLLM: true,
    enableTTS: true,
    autoPlayTTS: true,
    llmConfig: {
      apiKey,
      model: 'gpt-3.5-turbo',
      systemPrompt: 'You are a helpful voice assistant.',
      temperature: 0.7,
      maxTokens: 500
    },
    whisperConfig: {
      model: 'whisper-base'
    },
    ttsConfig: {
      voice: 'jenny',
      rate: 1.0,
      pitch: 1.0,
      volume: 1.0
    }
  };

  const [pipelineState, pipelineActions] = useVoicePipeline(options);

  // Handle events
  React.useEffect(() => {
    if (pipelineState.transcription) {
      onTranscription?.(pipelineState.transcription);
    }
  }, [pipelineState.transcription, onTranscription]);

  React.useEffect(() => {
    if (pipelineState.llmResponse) {
      onResponse?.(pipelineState.llmResponse);
    }
  }, [pipelineState.llmResponse, onResponse]);

  const handleToggle = async () => {
    try {
      if (!pipelineState.isInitialized) {
        await pipelineActions.initialize();
      }

      if (pipelineState.isListening) {
        await pipelineActions.stop();
      } else {
        await pipelineActions.start();
      }
    } catch (error) {
      console.error('Voice pipeline error:', error);
    }
  };

  return (
    <div className="voice-assistant">
      <button
        onClick={handleToggle}
        disabled={pipelineState.isProcessing}
        className={`voice-button ${pipelineState.isListening ? 'listening' : ''}`}
      >
        {pipelineState.isListening ? '🛑 Stop' : '🎤 Start'}
      </button>

      {pipelineState.isProcessing && (
        <div className="processing-indicator">Processing...</div>
      )}

      {pipelineState.error && (
        <div className="error-message">
          Error: {pipelineState.error.message}
        </div>
      )}
    </div>
  );
}
```

## Framework-Specific Integration

### React Integration with useVoicePipeline Hook

```typescript
import { useVoicePipeline } from '@runanywhere/react';
import type { UseVoicePipelineOptions } from '@runanywhere/react';

// Basic usage
function MyComponent() {
  const [state, actions] = useVoicePipeline({
    enableLLM: true,
    llmConfig: {
      apiKey: 'your-api-key',
      model: 'gpt-3.5-turbo'
    }
  });

  // Auto-initialize on mount
  React.useEffect(() => {
    if (!state.isInitialized) {
      actions.initialize();
    }
  }, []);

  return (
    <VoiceInterface state={state} actions={actions} />
  );
}

// With conversation management
function ConversationApp() {
  const [conversation, setConversation] = React.useState([]);
  const [state, actions] = useVoicePipeline(config);

  React.useEffect(() => {
    if (state.transcription && state.llmResponse) {
      setConversation(prev => [
        ...prev,
        { role: 'user', content: state.transcription },
        { role: 'assistant', content: state.llmResponse }
      ]);
    }
  }, [state.transcription, state.llmResponse]);

  return (
    <div>
      <ConversationHistory messages={conversation} />
      <VoiceControls state={state} actions={actions} />
    </div>
  );
}
```

### Vue.js Integration Patterns

```typescript
// Vue 3 Composition API
<template>
  <div class="voice-app">
    <button @click="toggle" :disabled="state.isProcessing">
      {{ buttonText }}
    </button>

    <div v-if="conversation.length">
      <div v-for="entry in conversation" :key="entry.id">
        <p :class="entry.type">{{ entry.text }}</p>
      </div>
    </div>

    <div v-if="state.error" class="error">
      {{ state.error.message }}
    </div>
  </div>
</template>

<script setup lang="ts">
import { useVoicePipeline } from '@runanywhere/vue';

const config = {
  enableLLM: true,
  llmConfig: {
    apiKey: process.env.VUE_APP_OPENAI_API_KEY,
    model: 'gpt-3.5-turbo'
  },
  autoInitialize: true
};

const {
  state,
  conversation,
  metrics,
  buttonText,
  isReady,
  initialize,
  start,
  stop,
  clearConversation
} = useVoicePipeline(config);

const toggle = async () => {
  if (state.isListening) {
    await stop();
  } else {
    await start();
  }
};
</script>
```

### Angular Integration Examples

```typescript
// Component
import { Component, OnInit, OnDestroy } from '@angular/core';
import { VoicePipelineService } from '@runanywhere/angular';
import { Observable } from 'rxjs';

@Component({
  selector: 'app-voice-chat',
  template: `
    <div class="voice-chat">
      <button
        (click)="toggle()"
        [disabled]="(state$ | async)?.isProcessing">
        {{ buttonText$ | async }}
      </button>

      <div *ngFor="let message of conversation$ | async">
        <p [ngClass]="message.type">{{ message.text }}</p>
      </div>

      <div *ngIf="(state$ | async)?.error" class="error">
        {{ (state$ | async)?.error?.message }}
      </div>
    </div>
  `
})
export class VoiceChatComponent implements OnInit, OnDestroy {
  state$ = this.voiceService.state$;
  conversation$ = this.voiceService.conversation$;
  buttonText$ = this.voiceService.buttonText$;
  isReady$ = this.voiceService.isReady$;

  constructor(private voiceService: VoicePipelineService) {}

  async ngOnInit() {
    await this.voiceService.initialize({
      enableLLM: true,
      llmConfig: {
        apiKey: environment.openaiApiKey,
        model: 'gpt-3.5-turbo'
      }
    });
  }

  async toggle() {
    const currentState = this.voiceService.currentState;
    if (currentState.isListening) {
      await this.voiceService.stop();
    } else {
      await this.voiceService.start();
    }
  }

  ngOnDestroy() {
    // Service handles cleanup automatically
  }
}

// Service injection in module
import { NgModule } from '@angular/core';
import { VoicePipelineService } from '@runanywhere/angular';

@NgModule({
  providers: [VoicePipelineService],
  // ...
})
export class AppModule {}
```

### Vanilla JavaScript Usage

```javascript
import { DIContainer } from '@runanywhere/core';
import { EnhancedVoicePipelineManager } from '@runanywhere/voice';

class VoiceApp {
  constructor() {
    this.container = new DIContainer();
    this.pipeline = null;
  }

  async initialize() {
    this.pipeline = new EnhancedVoicePipelineManager(this.container, {
      enableLLM: true,
      llmConfig: {
        apiKey: process.env.OPENAI_API_KEY,
        model: 'gpt-3.5-turbo'
      },
      autoPlayTTS: true
    });

    // Set up event listeners
    this.pipeline.on('transcription', (result) => {
      console.log('User said:', result.text);
      this.updateUI('user', result.text);
    });

    this.pipeline.on('llmResponse', (result) => {
      console.log('Assistant:', result.text);
      this.updateUI('assistant', result.text);
    });

    this.pipeline.on('error', (error) => {
      console.error('Pipeline error:', error);
      this.showError(error.message);
    });

    const result = await this.pipeline.initialize();
    if (!result.success) {
      throw result.error;
    }
  }

  async start() {
    if (!this.pipeline) {
      await this.initialize();
    }
    await this.pipeline.start();
  }

  async stop() {
    if (this.pipeline) {
      await this.pipeline.stop();
    }
  }

  updateUI(role, text) {
    const chatContainer = document.getElementById('chat');
    const message = document.createElement('div');
    message.className = `message ${role}`;
    message.textContent = text;
    chatContainer.appendChild(message);
  }

  showError(message) {
    const errorDiv = document.getElementById('error');
    errorDiv.textContent = message;
    errorDiv.style.display = 'block';
  }
}

// Usage
const app = new VoiceApp();
document.getElementById('startBtn').onclick = () => app.start();
document.getElementById('stopBtn').onclick = () => app.stop();
```

## Configuration Guide

### Pipeline Configuration Options

```typescript
interface EnhancedPipelineConfig {
  // Component toggles
  enableTranscription?: boolean; // Default: true
  enableLLM?: boolean;           // Default: false
  enableTTS?: boolean;           // Default: false
  autoPlayTTS?: boolean;         // Default: false

  // Voice Activity Detection
  vadConfig?: {
    threshold?: number;          // Voice detection sensitivity
    minSpeechFrames?: number;    // Minimum frames for speech
    maxSilenceFrames?: number;   // Max silence before cutoff
  };

  // Whisper (Speech-to-Text) Configuration
  whisperConfig?: {
    model?: 'whisper-tiny' | 'whisper-base' | 'whisper-small';
    language?: string;           // Language code (e.g., 'en', 'es')
    temperature?: number;        // Sampling temperature
    maxContextLength?: number;   // Maximum context length
  };

  // LLM Configuration
  llmConfig?: {
    apiKey: string;             // OpenAI API key
    baseUrl?: string;           // Custom API endpoint
    model?: string;             // Model name
    temperature?: number;        // Response creativity
    maxTokens?: number;         // Maximum response tokens
    systemPrompt?: string;      // System instructions
    streaming?: boolean;        // Enable streaming responses
  };

  // TTS Configuration
  ttsConfig?: {
    voice?: string;             // Voice ID
    rate?: number;              // Speech rate (0.5-2.0)
    pitch?: number;             // Voice pitch (0.5-2.0)
    volume?: number;            // Audio volume (0.0-1.0)
    format?: 'mp3' | 'wav';     // Audio format
  };

  // Performance Settings
  maxHistorySize?: number;      // Conversation history limit
}
```

### Service-Specific Configurations

#### Whisper Service Configuration

```typescript
interface WhisperConfig {
  model: 'whisper-tiny' | 'whisper-base' | 'whisper-small';
  language?: string;
  temperature?: number;
  compressionRatioThreshold?: number;
  logProbThreshold?: number;
  noSpeechThreshold?: number;
  condition?: {
    timestamp: boolean;
    noSpeech: boolean;
  };
}

// Usage
const whisperConfig: Partial<WhisperConfig> = {
  model: 'whisper-base',
  language: 'en',
  temperature: 0.0,
  condition: {
    timestamp: false,
    noSpeech: true
  }
};
```

#### LLM Service Configuration

```typescript
interface LLMConfig {
  apiKey: string;
  baseUrl?: string;
  model?: string;
  temperature?: number;
  maxTokens?: number;
  topP?: number;
  frequencyPenalty?: number;
  presencePenalty?: number;
  systemPrompt?: string;
  streaming?: boolean;
  timeout?: number;
}

// Usage
const llmConfig: Partial<LLMConfig> = {
  apiKey: process.env.OPENAI_API_KEY!,
  model: 'gpt-3.5-turbo',
  temperature: 0.7,
  maxTokens: 500,
  systemPrompt: 'You are a helpful voice assistant. Keep responses concise and conversational.',
  streaming: true,
  timeout: 30000
};
```

#### TTS Service Configuration

```typescript
interface TTSConfig {
  voice?: string;
  rate?: number;
  pitch?: number;
  volume?: number;
  format?: 'mp3' | 'wav' | 'ogg';
  quality?: 'low' | 'medium' | 'high';
  streaming?: boolean;
}

// Usage
const ttsConfig: Partial<TTSConfig> = {
  voice: 'jenny',
  rate: 1.0,
  pitch: 1.0,
  volume: 0.8,
  format: 'mp3',
  quality: 'high',
  streaming: true
};
```

### Environment Setup

#### Environment Variables

```bash
# .env file
REACT_APP_OPENAI_API_KEY=sk-your-openai-key
REACT_APP_LLM_ENDPOINT=https://api.openai.com/v1
REACT_APP_WHISPER_MODEL=whisper-base
REACT_APP_TTS_VOICE=jenny
REACT_APP_DEBUG_MODE=false
```

#### Build Configuration (Vite)

```typescript
// vite.config.ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  optimizeDeps: {
    exclude: ['@runanywhere/voice']
  },
  worker: {
    format: 'es'
  },
  build: {
    target: 'esnext',
    rollupOptions: {
      output: {
        manualChunks: {
          'voice-sdk': ['@runanywhere/voice'],
          'ml-models': ['@runanywhere/transcription', '@runanywhere/tts']
        }
      }
    }
  },
  server: {
    headers: {
      'Cross-Origin-Embedder-Policy': 'require-corp',
      'Cross-Origin-Opener-Policy': 'same-origin'
    }
  }
});
```

#### Webpack Configuration

```javascript
// webpack.config.js
module.exports = {
  resolve: {
    fallback: {
      "stream": require.resolve("stream-browserify"),
      "buffer": require.resolve("buffer")
    }
  },
  plugins: [
    new webpack.ProvidePlugin({
      Buffer: ['buffer', 'Buffer'],
    }),
  ],
  module: {
    rules: [
      {
        test: /\.worker\.js$/,
        use: { loader: 'worker-loader' }
      }
    ]
  }
};
```

### API Key Management

```typescript
// Secure API key management
class ApiKeyManager {
  private apiKey: string | null = null;

  setApiKey(key: string) {
    if (!key.startsWith('sk-')) {
      throw new Error('Invalid OpenAI API key format');
    }
    this.apiKey = key;
    // Store securely (consider encryption)
    sessionStorage.setItem('oai_key', btoa(key));
  }

  getApiKey(): string | null {
    if (this.apiKey) return this.apiKey;

    const stored = sessionStorage.getItem('oai_key');
    if (stored) {
      this.apiKey = atob(stored);
      return this.apiKey;
    }

    return null;
  }

  clearApiKey() {
    this.apiKey = null;
    sessionStorage.removeItem('oai_key');
  }
}

// Usage in configuration
const keyManager = new ApiKeyManager();

const pipelineConfig = {
  llmConfig: {
    apiKey: keyManager.getApiKey() || '',
    // ... other config
  }
};
```

## Advanced Usage Patterns

### Custom Service Implementations

```typescript
// Custom LLM Service
import { LLMService, LLMConfig } from '@runanywhere/llm';

class CustomLLMService extends LLMService {
  constructor(config: Partial<LLMConfig>) {
    super(config);
  }

  async complete(prompt: string): Promise<Result<CompletionResult, Error>> {
    // Custom LLM implementation
    try {
      const response = await fetch('/api/custom-llm', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ prompt, config: this.config })
      });

      const data = await response.json();

      return Result.ok({
        text: data.response,
        usage: data.usage,
        latency: Date.now() - startTime
      });
    } catch (error) {
      return Result.err(error instanceof Error ? error : new Error(String(error)));
    }
  }
}

// Register custom service
const container = new DIContainer();
container.register('CustomLLMService', () => new CustomLLMService(config));
```

### Event Handling and Lifecycle Management

```typescript
class VoicePipelineManager {
  private pipeline: EnhancedVoicePipelineManager;
  private eventHandlers: Map<string, Function[]> = new Map();

  constructor(config: EnhancedPipelineConfig) {
    this.pipeline = new EnhancedVoicePipelineManager(container, config);
    this.setupEventHandlers();
  }

  private setupEventHandlers() {
    // Transcription events
    this.pipeline.on('transcriptionStart', () => {
      this.emit('processing:start', 'transcription');
    });

    this.pipeline.on('partialTranscription', (partial) => {
      this.emit('transcription:partial', partial);
    });

    this.pipeline.on('transcription', (result) => {
      this.emit('transcription:complete', result);
      this.emit('processing:complete', 'transcription', result.latency);
    });

    // LLM events
    this.pipeline.on('llmStart', (data) => {
      this.emit('processing:start', 'llm');
    });

    this.pipeline.on('llmToken', (token) => {
      this.emit('llm:streaming', token);
    });

    this.pipeline.on('llmResponse', (result) => {
      this.emit('llm:complete', result);
      this.emit('processing:complete', 'llm', result.latency);
    });

    // TTS events
    this.pipeline.on('ttsStart', (data) => {
      this.emit('processing:start', 'tts');
    });

    this.pipeline.on('ttsProgress', (progress) => {
      this.emit('tts:progress', progress);
    });

    this.pipeline.on('ttsComplete', (result) => {
      this.emit('tts:complete', result);
      this.emit('processing:complete', 'tts', result.latency);
    });

    // Error handling
    this.pipeline.on('error', (error) => {
      this.handleError(error);
    });
  }

  on(event: string, handler: Function) {
    if (!this.eventHandlers.has(event)) {
      this.eventHandlers.set(event, []);
    }
    this.eventHandlers.get(event)!.push(handler);
  }

  private emit(event: string, ...args: any[]) {
    const handlers = this.eventHandlers.get(event);
    if (handlers) {
      handlers.forEach(handler => handler(...args));
    }
  }

  private handleError(error: Error) {
    console.error('Pipeline error:', error);
    this.emit('error', {
      type: 'pipeline_error',
      error,
      timestamp: Date.now()
    });
  }

  // Lifecycle management
  async gracefulShutdown() {
    console.log('Shutting down voice pipeline...');

    if (this.pipeline) {
      await this.pipeline.stop();
      this.pipeline.destroy();
    }

    this.eventHandlers.clear();
    console.log('Pipeline shutdown complete');
  }
}
```

### Error Handling Best Practices

```typescript
class ErrorBoundary extends React.Component {
  constructor(props: any) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error) {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    // Log to monitoring service
    console.error('Voice SDK Error:', error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="error-boundary">
          <h2>Voice feature temporarily unavailable</h2>
          <button onClick={() => window.location.reload()}>
            Retry
          </button>
        </div>
      );
    }

    return this.props.children;
  }
}

// Error handling in hooks
function useVoiceWithErrorHandling(config: UseVoicePipelineOptions) {
  const [state, actions] = useVoicePipeline(config);
  const [retryCount, setRetryCount] = React.useState(0);

  const handleError = React.useCallback(async (error: Error) => {
    console.error('Voice pipeline error:', error);

    // Retry logic
    if (retryCount < 3) {
      setRetryCount(prev => prev + 1);

      // Wait before retry
      await new Promise(resolve => setTimeout(resolve, 1000 * retryCount));

      try {
        await actions.initialize();
      } catch (retryError) {
        console.error('Retry failed:', retryError);
      }
    }
  }, [retryCount, actions]);

  React.useEffect(() => {
    if (state.error) {
      handleError(state.error);
    }
  }, [state.error, handleError]);

  return { state, actions, retryCount };
}
```

### Performance Optimization Tips

```typescript
// Lazy loading for better performance
const VoiceAssistant = React.lazy(() => import('./VoiceAssistant'));

function App() {
  return (
    <React.Suspense fallback={<div>Loading voice features...</div>}>
      <VoiceAssistant />
    </React.Suspense>
  );
}

// Memory management
class VoiceMemoryManager {
  private static instance: VoiceMemoryManager;
  private pipelines: Map<string, EnhancedVoicePipelineManager> = new Map();

  static getInstance() {
    if (!VoiceMemoryManager.instance) {
      VoiceMemoryManager.instance = new VoiceMemoryManager();
    }
    return VoiceMemoryManager.instance;
  }

  createPipeline(id: string, config: EnhancedPipelineConfig) {
    if (this.pipelines.has(id)) {
      this.destroyPipeline(id);
    }

    const pipeline = new EnhancedVoicePipelineManager(container, config);
    this.pipelines.set(id, pipeline);
    return pipeline;
  }

  destroyPipeline(id: string) {
    const pipeline = this.pipelines.get(id);
    if (pipeline) {
      pipeline.destroy();
      this.pipelines.delete(id);
    }
  }

  cleanup() {
    this.pipelines.forEach(pipeline => pipeline.destroy());
    this.pipelines.clear();
  }
}

// Performance monitoring
class PerformanceMonitor {
  private metrics: Map<string, number[]> = new Map();

  recordLatency(operation: string, latency: number) {
    if (!this.metrics.has(operation)) {
      this.metrics.set(operation, []);
    }

    const values = this.metrics.get(operation)!;
    values.push(latency);

    // Keep only last 100 measurements
    if (values.length > 100) {
      values.shift();
    }
  }

  getAverageLatency(operation: string): number {
    const values = this.metrics.get(operation) || [];
    if (values.length === 0) return 0;

    return values.reduce((sum, val) => sum + val, 0) / values.length;
  }

  getMetricsReport() {
    const report: Record<string, any> = {};

    this.metrics.forEach((values, operation) => {
      report[operation] = {
        average: this.getAverageLatency(operation),
        min: Math.min(...values),
        max: Math.max(...values),
        count: values.length
      };
    });

    return report;
  }
}
```

## API Reference

### Core Types

```typescript
// Pipeline State
interface VoicePipelineState {
  isInitialized: boolean;
  isListening: boolean;
  isProcessing: boolean;
  isPlaying: boolean;
  error: Error | null;
  transcription: string;
  llmResponse: string;
}

// Pipeline Actions
interface VoicePipelineActions {
  initialize: () => Promise<void>;
  start: () => Promise<void>;
  stop: () => Promise<void>;
  pause: () => Promise<void>;
  resume: () => Promise<void>;
  destroy: () => void;
}

// Configuration Options
interface UseVoicePipelineOptions extends EnhancedPipelineConfig {
  autoStart?: boolean;
}

// Results
interface TranscriptionResult {
  text: string;
  confidence?: number;
  language?: string;
  segments?: TranscriptionSegment[];
  latency: number;
}

interface CompletionResult {
  text: string;
  usage: {
    promptTokens: number;
    completionTokens: number;
    totalTokens: number;
  };
  model: string;
  latency: number;
}

interface SynthesisResult {
  audioBuffer: ArrayBuffer;
  duration: number;
  format: string;
  sampleRate: number;
  latency: number;
}
```

### Hook Signatures

#### React Hook

```typescript
function useVoicePipeline(
  options?: UseVoicePipelineOptions
): [VoicePipelineState, VoicePipelineActions];

// Usage
const [state, actions] = useVoicePipeline({
  enableLLM: true,
  llmConfig: { apiKey: 'sk-...' }
});
```

#### Vue Composable

```typescript
function useVoicePipeline(config?: VoicePipelineConfig): {
  state: Readonly<VoicePipelineState>;
  conversation: Readonly<ConversationEntry[]>;
  metrics: Readonly<VoiceMetrics>;
  buttonText: ComputedRef<string>;
  isReady: ComputedRef<boolean>;
  initialize: () => Promise<void>;
  start: () => Promise<void>;
  stop: () => Promise<void>;
  clearConversation: () => void;
  clearError: () => void;
  destroy: () => void;
};
```

#### Angular Service

```typescript
@Injectable({
  providedIn: 'root'
})
class VoicePipelineService {
  // Observables
  readonly state$: Observable<VoicePipelineState>;
  readonly conversation$: Observable<ConversationEntry[]>;
  readonly metrics$: Observable<VoiceMetrics>;
  readonly isReady$: Observable<boolean>;
  readonly buttonText$: Observable<string>;

  // Current state getter
  get currentState(): VoicePipelineState;

  // Methods
  initialize(config?: VoicePipelineConfig): Promise<void>;
  start(): Promise<void>;
  stop(): Promise<void>;
  clearConversation(): void;
  clearError(): void;
}
```

### Event Types and Payloads

```typescript
// Pipeline Events
interface EnhancedPipelineEvents {
  // Lifecycle
  'started': void;
  'stopped': void;
  'error': Error;

  // VAD Events
  'vadSpeechStart': void;
  'vadSpeechEnd': Float32Array;

  // Transcription Events
  'transcriptionStart': void;
  'partialTranscription': { text: string; timestamp?: number };
  'transcription': TranscriptionResult;

  // LLM Events
  'llmStart': { prompt: string };
  'llmToken': { token: string; position: number };
  'llmResponse': CompletionResult;

  // TTS Events
  'ttsStart': { text: string };
  'ttsProgress': { text: string; progress: number };
  'ttsComplete': SynthesisResult;
  'ttsPlaybackStart': void;
  'ttsPlaybackEnd': void;

  // Pipeline Complete
  'pipelineComplete': {
    transcription: TranscriptionResult;
    llmResponse?: CompletionResult;
    ttsResult?: SynthesisResult;
  };
}
```

### Configuration Schemas

```typescript
// Whisper Configuration Schema
interface WhisperConfig {
  model: 'whisper-tiny' | 'whisper-base' | 'whisper-small';
  language?: string;
  temperature?: number; // 0.0 - 1.0
  compressionRatioThreshold?: number;
  logProbThreshold?: number;
  noSpeechThreshold?: number;
  condition?: {
    timestamp: boolean;
    noSpeech: boolean;
  };
}

// LLM Configuration Schema
interface LLMConfig {
  apiKey: string;
  baseUrl?: string;
  model?: string;
  temperature?: number; // 0.0 - 2.0
  maxTokens?: number; // 1 - 4096
  topP?: number; // 0.0 - 1.0
  frequencyPenalty?: number; // -2.0 - 2.0
  presencePenalty?: number; // -2.0 - 2.0
  systemPrompt?: string;
  streaming?: boolean;
  timeout?: number; // milliseconds
}

// TTS Configuration Schema
interface TTSConfig {
  voice?: string;
  rate?: number; // 0.5 - 2.0
  pitch?: number; // 0.5 - 2.0
  volume?: number; // 0.0 - 1.0
  format?: 'mp3' | 'wav' | 'ogg';
  quality?: 'low' | 'medium' | 'high';
  streaming?: boolean;
}
```

## Common Use Cases

### Voice Chat Application

```typescript
interface Message {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  timestamp: number;
  audioUrl?: string;
}

function VoiceChatApp() {
  const [messages, setMessages] = React.useState<Message[]>([]);
  const [isRecording, setIsRecording] = React.useState(false);

  const [pipelineState, pipelineActions] = useVoicePipeline({
    enableTranscription: true,
    enableLLM: true,
    enableTTS: true,
    autoPlayTTS: true,
    llmConfig: {
      apiKey: process.env.REACT_APP_OPENAI_API_KEY!,
      systemPrompt: "You are a friendly conversational AI assistant. Keep responses natural and engaging."
    }
  });

  const handleStartRecording = async () => {
    try {
      if (!pipelineState.isInitialized) {
        await pipelineActions.initialize();
      }
      await pipelineActions.start();
      setIsRecording(true);
    } catch (error) {
      console.error('Failed to start recording:', error);
    }
  };

  const handleStopRecording = async () => {
    try {
      await pipelineActions.stop();
      setIsRecording(false);
    } catch (error) {
      console.error('Failed to stop recording:', error);
    }
  };

  // Handle new messages
  React.useEffect(() => {
    if (pipelineState.transcription && pipelineState.llmResponse) {
      const timestamp = Date.now();
      setMessages(prev => [
        ...prev,
        {
          id: `user-${timestamp}`,
          role: 'user',
          content: pipelineState.transcription,
          timestamp
        },
        {
          id: `assistant-${timestamp}`,
          role: 'assistant',
          content: pipelineState.llmResponse,
          timestamp: timestamp + 1
        }
      ]);
    }
  }, [pipelineState.transcription, pipelineState.llmResponse]);

  return (
    <div className="voice-chat">
      <div className="messages">
        {messages.map(message => (
          <div key={message.id} className={`message ${message.role}`}>
            <div className="content">{message.content}</div>
            <div className="timestamp">
              {new Date(message.timestamp).toLocaleTimeString()}
            </div>
          </div>
        ))}
      </div>

      <div className="controls">
        <button
          onMouseDown={handleStartRecording}
          onMouseUp={handleStopRecording}
          disabled={pipelineState.isProcessing}
          className={`record-btn ${isRecording ? 'recording' : ''}`}
        >
          {isRecording ? '🔴 Recording' : '🎤 Hold to Talk'}
        </button>
      </div>

      {pipelineState.isProcessing && (
        <div className="processing">Processing...</div>
      )}
    </div>
  );
}
```

### Voice Commands and Controls

```typescript
interface VoiceCommand {
  pattern: RegExp | string;
  handler: (match: RegExpMatchArray | null, fullText: string) => void;
  description: string;
}

class VoiceCommandProcessor {
  private commands: VoiceCommand[] = [];

  registerCommand(command: VoiceCommand) {
    this.commands.push(command);
  }

  processTranscription(text: string): boolean {
    const normalizedText = text.toLowerCase().trim();

    for (const command of this.commands) {
      let match: RegExpMatchArray | null = null;

      if (command.pattern instanceof RegExp) {
        match = normalizedText.match(command.pattern);
      } else if (normalizedText.includes(command.pattern.toLowerCase())) {
        match = [normalizedText];
      }

      if (match) {
        command.handler(match, text);
        return true; // Command handled
      }
    }

    return false; // No command matched
  }
}

function VoiceControlledApp() {
  const [currentPage, setCurrentPage] = React.useState('home');
  const [isPlaying, setIsPlaying] = React.useState(false);
  const commandProcessor = React.useMemo(() => new VoiceCommandProcessor(), []);

  const [pipelineState, pipelineActions] = useVoicePipeline({
    enableTranscription: true,
    enableLLM: false, // Only transcription for commands
    enableTTS: true,
    llmConfig: {
      apiKey: process.env.REACT_APP_OPENAI_API_KEY!
    }
  });

  // Set up voice commands
  React.useEffect(() => {
    commandProcessor.registerCommand({
      pattern: /go to (home|settings|profile|about)/i,
      handler: (match) => {
        const page = match![1].toLowerCase();
        setCurrentPage(page);
        speak(`Navigating to ${page}`);
      },
      description: 'Navigate to different pages'
    });

    commandProcessor.registerCommand({
      pattern: /(play|pause) music/i,
      handler: (match) => {
        const action = match![1].toLowerCase();
        setIsPlaying(action === 'play');
        speak(`${action === 'play' ? 'Playing' : 'Pausing'} music`);
      },
      description: 'Control music playback'
    });

    commandProcessor.registerCommand({
      pattern: /what can I say/i,
      handler: () => {
        const commands = commandProcessor.getAllCommands();
        speak(`You can say: ${commands.join(', ')}`);
      },
      description: 'List available commands'
    });
  }, [commandProcessor]);

  // Process transcription for commands
  React.useEffect(() => {
    if (pipelineState.transcription) {
      const handled = commandProcessor.processTranscription(pipelineState.transcription);

      if (!handled) {
        speak("Sorry, I didn't recognize that command");
      }
    }
  }, [pipelineState.transcription, commandProcessor]);

  const speak = async (text: string) => {
    // Use TTS service to provide feedback
    console.log('Speaking:', text);
  };

  return (
    <div className="voice-controlled-app">
      <div className="current-page">
        <h1>{currentPage.charAt(0).toUpperCase() + currentPage.slice(1)}</h1>
      </div>

      <div className="voice-indicator">
        {pipelineState.isListening && (
          <div className="listening">Listening for commands...</div>
        )}
      </div>

      <button
        onClick={() => pipelineState.isListening ? pipelineActions.stop() : pipelineActions.start()}
      >
        {pipelineState.isListening ? 'Stop Listening' : 'Start Voice Control'}
      </button>
    </div>
  );
}
```

### Real-time Transcription

```typescript
function LiveTranscriptionApp() {
  const [transcript, setTranscript] = React.useState('');
  const [isRecording, setIsRecording] = React.useState(false);
  const [wordCount, setWordCount] = React.useState(0);

  const [pipelineState, pipelineActions] = useVoicePipeline({
    enableTranscription: true,
    enableLLM: false,
    enableTTS: false,
    whisperConfig: {
      model: 'whisper-base',
      temperature: 0.0 // More deterministic for transcription
    }
  });

  // Update transcript and word count
  React.useEffect(() => {
    if (pipelineState.transcription) {
      setTranscript(prev => prev + ' ' + pipelineState.transcription);
      setWordCount(prev => prev + pipelineState.transcription.split(' ').length);
    }
  }, [pipelineState.transcription]);

  const startRecording = async () => {
    try {
      if (!pipelineState.isInitialized) {
        await pipelineActions.initialize();
      }
      await pipelineActions.start();
      setIsRecording(true);
    } catch (error) {
      console.error('Failed to start recording:', error);
    }
  };

  const stopRecording = async () => {
    try {
      await pipelineActions.stop();
      setIsRecording(false);
    } catch (error) {
      console.error('Failed to stop recording:', error);
    }
  };

  const clearTranscript = () => {
    setTranscript('');
    setWordCount(0);
  };

  const downloadTranscript = () => {
    const blob = new Blob([transcript], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `transcript-${new Date().toISOString().split('T')[0]}.txt`;
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div className="transcription-app">
      <div className="controls">
        <button
          onClick={isRecording ? stopRecording : startRecording}
          className={isRecording ? 'stop' : 'start'}
        >
          {isRecording ? '⏹️ Stop' : '🎤 Start'} Recording
        </button>
        <button onClick={clearTranscript}>Clear</button>
        <button onClick={downloadTranscript} disabled={!transcript}>
          Download
        </button>
      </div>

      <div className="stats">
        <span>Word Count: {wordCount}</span>
        <span>Status: {isRecording ? 'Recording' : 'Stopped'}</span>
        {pipelineState.isProcessing && <span>Processing...</span>}
      </div>

      <div className="transcript-area">
        <textarea
          value={transcript}
          onChange={(e) => setTranscript(e.target.value)}
          placeholder="Transcript will appear here..."
          rows={20}
          cols={80}
        />
      </div>

      {pipelineState.error && (
        <div className="error">
          Error: {pipelineState.error.message}
        </div>
      )}
    </div>
  );
}
```

### AI-Powered Voice Assistant

```typescript
interface AssistantContext {
  userName?: string;
  preferences?: Record<string, any>;
  conversationHistory: Message[];
}

function AIVoiceAssistant() {
  const [context, setContext] = React.useState<AssistantContext>({
    conversationHistory: []
  });
  const [isThinking, setIsThinking] = React.useState(false);

  const [pipelineState, pipelineActions] = useVoicePipeline({
    enableTranscription: true,
    enableLLM: true,
    enableTTS: true,
    autoPlayTTS: true,
    llmConfig: {
      apiKey: process.env.REACT_APP_OPENAI_API_KEY!,
      model: 'gpt-4',
      temperature: 0.8,
      systemPrompt: `You are a helpful AI assistant. You have access to the user's conversation history and preferences.
        Be conversational, helpful, and remember context from previous interactions.
        Keep responses concise but informative.`,
    },
    ttsConfig: {
      voice: 'jenny',
      rate: 1.1,
      pitch: 1.0
    }
  });

  // Handle new conversations
  React.useEffect(() => {
    if (pipelineState.transcription && pipelineState.llmResponse) {
      const userMessage: Message = {
        id: `user-${Date.now()}`,
        role: 'user',
        content: pipelineState.transcription,
        timestamp: Date.now()
      };

      const assistantMessage: Message = {
        id: `assistant-${Date.now()}`,
        role: 'assistant',
        content: pipelineState.llmResponse,
        timestamp: Date.now() + 1
      };

      setContext(prev => ({
        ...prev,
        conversationHistory: [...prev.conversationHistory, userMessage, assistantMessage]
      }));
    }
  }, [pipelineState.transcription, pipelineState.llmResponse]);

  // Show thinking indicator during LLM processing
  React.useEffect(() => {
    if (pipelineState.isProcessing) {
      const timer = setTimeout(() => setIsThinking(true), 1000);
      return () => clearTimeout(timer);
    } else {
      setIsThinking(false);
    }
  }, [pipelineState.isProcessing]);

  const handleVoiceToggle = async () => {
    try {
      if (pipelineState.isListening) {
        await pipelineActions.stop();
      } else {
        if (!pipelineState.isInitialized) {
          await pipelineActions.initialize();
        }
        await pipelineActions.start();
      }
    } catch (error) {
      console.error('Voice assistant error:', error);
    }
  };

  const clearHistory = () => {
    setContext(prev => ({ ...prev, conversationHistory: [] }));
  };

  const exportConversation = () => {
    const conversation = context.conversationHistory
      .map(msg => `${msg.role.toUpperCase()}: ${msg.content}`)
      .join('\n\n');

    const blob = new Blob([conversation], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `conversation-${new Date().toISOString().split('T')[0]}.txt`;
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div className="ai-assistant">
      <div className="header">
        <h1>AI Voice Assistant</h1>
        <div className="controls">
          <button onClick={clearHistory}>Clear History</button>
          <button onClick={exportConversation} disabled={!context.conversationHistory.length}>
            Export
          </button>
        </div>
      </div>

      <div className="conversation">
        {context.conversationHistory.map(message => (
          <div key={message.id} className={`message ${message.role}`}>
            <div className="avatar">
              {message.role === 'user' ? '👤' : '🤖'}
            </div>
            <div className="content">
              <div className="text">{message.content}</div>
              <div className="timestamp">
                {new Date(message.timestamp).toLocaleTimeString()}
              </div>
            </div>
          </div>
        ))}

        {isThinking && (
          <div className="message assistant thinking">
            <div className="avatar">🤖</div>
            <div className="content">
              <div className="thinking-indicator">
                <span></span><span></span><span></span>
              </div>
            </div>
          </div>
        )}
      </div>

      <div className="voice-control">
        <button
          onClick={handleVoiceToggle}
          className={`voice-btn ${pipelineState.isListening ? 'active' : ''}`}
          disabled={pipelineState.isProcessing}
        >
          {pipelineState.isListening ? '🔴 Listening...' : '🎤 Talk to Assistant'}
        </button>

        <div className="status">
          {pipelineState.isProcessing && 'Processing your request...'}
          {pipelineState.isPlaying && '🔊 Speaking...'}
          {pipelineState.error && `Error: ${pipelineState.error.message}`}
        </div>
      </div>
    </div>
  );
}
```

## Troubleshooting and Best Practices

### Common Issues and Solutions

#### Issue: Microphone Permission Denied

**Problem**: Browser blocks microphone access
**Solution**:

```typescript
// Check permissions before initializing
async function checkMicrophonePermission(): Promise<boolean> {
  try {
    const result = await navigator.permissions.query({ name: 'microphone' as PermissionName });

    if (result.state === 'denied') {
      throw new Error('Microphone permission denied. Please enable in browser settings.');
    }

    // Test microphone access
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    stream.getTracks().forEach(track => track.stop());

    return true;
  } catch (error) {
    console.error('Microphone permission check failed:', error);
    return false;
  }
}

// Use in component
function VoiceApp() {
  const [hasPermission, setHasPermission] = React.useState<boolean | null>(null);

  React.useEffect(() => {
    checkMicrophonePermission().then(setHasPermission);
  }, []);

  if (hasPermission === false) {
    return (
      <div className="permission-error">
        <h2>Microphone Access Required</h2>
        <p>Please enable microphone access in your browser settings to use voice features.</p>
        <button onClick={() => window.location.reload()}>Retry</button>
      </div>
    );
  }

  // Rest of component...
}
```

#### Issue: HTTPS Required Error

**Problem**: WebRTC requires HTTPS in production
**Solution**:

```typescript
// Check for HTTPS
function checkSecureContext(): boolean {
  if (!window.isSecureContext) {
    console.error('Voice features require HTTPS or localhost');
    return false;
  }
  return true;
}

// Add to development server config
// vite.config.ts
export default defineConfig({
  server: {
    https: true, // Enable HTTPS for development
    // OR use mkcert for local HTTPS certificates
  }
});
```

#### Issue: Web Worker Loading Failures

**Problem**: Workers fail to load in production builds
**Solution**:

```typescript
// vite.config.ts - Proper worker configuration
export default defineConfig({
  worker: {
    format: 'es',
    plugins: () => [
      // Add any worker-specific plugins
    ]
  },
  build: {
    rollupOptions: {
      output: {
        // Ensure workers are properly chunked
        manualChunks: (id) => {
          if (id.includes('worker')) {
            return 'workers';
          }
        }
      }
    }
  }
});

// Dynamic worker import with fallback
async function loadWorker(): Promise<Worker> {
  try {
    // Try to load worker
    const worker = new Worker(
      new URL('../workers/audio-processor.worker.ts', import.meta.url),
      { type: 'module' }
    );
    return worker;
  } catch (error) {
    console.warn('Worker loading failed, using fallback:', error);
    // Implement fallback without worker
    throw new Error('Worker support required');
  }
}
```

#### Issue: Model Loading Timeouts

**Problem**: Large models fail to load on slow connections
**Solution**:

```typescript
// Progressive model loading with timeout handling
class ModelLoader {
  async loadWithRetry<T>(
    loadFn: () => Promise<T>,
    maxRetries: number = 3,
    timeoutMs: number = 30000
  ): Promise<T> {
    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        return await Promise.race([
          loadFn(),
          new Promise<never>((_, reject) =>
            setTimeout(() => reject(new Error('Load timeout')), timeoutMs)
          )
        ]);
      } catch (error) {
        console.warn(`Model load attempt ${attempt} failed:`, error);

        if (attempt === maxRetries) {
          throw error;
        }

        // Exponential backoff
        await new Promise(resolve => setTimeout(resolve, 1000 * attempt));
      }
    }

    throw new Error('All retry attempts failed');
  }
}

// Use adaptive model selection based on connection
function selectOptimalModel(): 'whisper-tiny' | 'whisper-base' | 'whisper-small' {
  const connection = (navigator as any).connection;

  if (connection) {
    if (connection.effectiveType === 'slow-2g' || connection.effectiveType === '2g') {
      return 'whisper-tiny';
    } else if (connection.effectiveType === '3g') {
      return 'whisper-base';
    }
  }

  return 'whisper-base'; // Default
}
```

### Performance Considerations

#### Memory Management

```typescript
// Implement proper cleanup
class VoiceAppManager {
  private pipeline: EnhancedVoicePipelineManager | null = null;
  private cleanupTimer: number | null = null;

  async initialize(config: EnhancedPipelineConfig) {
    // Clean up existing pipeline
    this.cleanup();

    this.pipeline = new EnhancedVoicePipelineManager(container, config);

    // Set up automatic cleanup
    this.cleanupTimer = window.setTimeout(() => {
      if (this.pipeline && !this.pipeline.isHealthy()) {
        console.warn('Pipeline unhealthy, cleaning up');
        this.cleanup();
      }
    }, 300000); // 5 minutes

    return this.pipeline.initialize();
  }

  cleanup() {
    if (this.cleanupTimer) {
      clearTimeout(this.cleanupTimer);
      this.cleanupTimer = null;
    }

    if (this.pipeline) {
      this.pipeline.destroy();
      this.pipeline = null;
    }

    // Force garbage collection if available
    if ('gc' in window) {
      (window as any).gc();
    }
  }
}

// Monitor memory usage
class MemoryMonitor {
  private static instance: MemoryMonitor;

  static getInstance() {
    if (!MemoryMonitor.instance) {
      MemoryMonitor.instance = new MemoryMonitor();
    }
    return MemoryMonitor.instance;
  }

  getCurrentUsage(): number {
    return (performance as any).memory?.usedJSHeapSize || 0;
  }

  checkMemoryPressure(): boolean {
    const memory = (performance as any).memory;
    if (!memory) return false;

    const usageRatio = memory.usedJSHeapSize / memory.jsHeapSizeLimit;
    return usageRatio > 0.8; // 80% threshold
  }

  startMonitoring(callback: (usage: number) => void) {
    setInterval(() => {
      callback(this.getCurrentUsage());

      if (this.checkMemoryPressure()) {
        console.warn('High memory usage detected');
      }
    }, 5000);
  }
}
```

#### Optimize for Mobile Devices

```typescript
// Mobile-specific optimizations
function getMobileOptimizedConfig(): Partial<EnhancedPipelineConfig> {
  const isMobile = /Android|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);
  const isLowEnd = (navigator as any).deviceMemory < 4;

  if (!isMobile) {
    return {}; // Use default config for desktop
  }

  return {
    whisperConfig: {
      model: isLowEnd ? 'whisper-tiny' : 'whisper-base'
    },
    maxHistorySize: 10, // Limit conversation history
    vadConfig: {
      // Reduce VAD sensitivity to save battery
      threshold: 0.7
    }
  };
}

// Battery-aware processing
class BatteryAwareProcessor {
  private batteryLevel: number = 1;
  private isCharging: boolean = true;

  async initialize() {
    if ('getBattery' in navigator) {
      const battery = await (navigator as any).getBattery();
      this.batteryLevel = battery.level;
      this.isCharging = battery.charging;

      battery.addEventListener('levelchange', () => {
        this.batteryLevel = battery.level;
        this.adjustProcessing();
      });

      battery.addEventListener('chargingchange', () => {
        this.isCharging = battery.charging;
        this.adjustProcessing();
      });
    }
  }

  shouldLimitProcessing(): boolean {
    return this.batteryLevel < 0.2 && !this.isCharging;
  }

  adjustProcessing() {
    if (this.shouldLimitProcessing()) {
      console.log('Low battery detected, reducing processing');
      // Implement power-saving measures
    }
  }
}
```

### Browser Compatibility Notes

#### Feature Detection

```typescript
// Comprehensive feature detection
class BrowserCompatibility {
  static checkCompatibility(): { compatible: boolean; missing: string[] } {
    const missing: string[] = [];

    // Check for required APIs
    if (!navigator.mediaDevices?.getUserMedia) {
      missing.push('getUserMedia');
    }

    if (!window.AudioContext && !(window as any).webkitAudioContext) {
      missing.push('Web Audio API');
    }

    if (!Worker) {
      missing.push('Web Workers');
    }

    if (!WebAssembly) {
      missing.push('WebAssembly');
    }

    if (!window.isSecureContext) {
      missing.push('Secure Context (HTTPS)');
    }

    return {
      compatible: missing.length === 0,
      missing
    };
  }

  static getPolyfills(): Promise<void>[] {
    const polyfills: Promise<void>[] = [];

    // AudioContext polyfill
    if (!(window as any).AudioContext && (window as any).webkitAudioContext) {
      (window as any).AudioContext = (window as any).webkitAudioContext;
    }

    return polyfills;
  }
}

// Use in application
function App() {
  const [compatibility, setCompatibility] = React.useState<{ compatible: boolean; missing: string[] } | null>(null);

  React.useEffect(() => {
    const check = BrowserCompatibility.checkCompatibility();
    setCompatibility(check);

    if (!check.compatible) {
      console.warn('Browser compatibility issues:', check.missing);
    }
  }, []);

  if (compatibility && !compatibility.compatible) {
    return (
      <div className="compatibility-error">
        <h2>Browser Not Supported</h2>
        <p>The following features are required but not available:</p>
        <ul>
          {compatibility.missing.map(feature => (
            <li key={feature}>{feature}</li>
          ))}
        </ul>
        <p>Please use a modern browser like Chrome, Firefox, or Safari.</p>
      </div>
    );
  }

  return <VoiceApp />;
}
```

### Production Deployment Tips

#### Environment Configuration

```typescript
// Production-ready configuration
const productionConfig: EnhancedPipelineConfig = {
  // Optimize for production
  whisperConfig: {
    model: process.env.NODE_ENV === 'development' ? 'whisper-tiny' : 'whisper-base'
  },

  llmConfig: {
    apiKey: process.env.REACT_APP_OPENAI_API_KEY!,
    baseUrl: process.env.REACT_APP_LLM_ENDPOINT || 'https://api.openai.com/v1',
    timeout: 30000,
    model: 'gpt-3.5-turbo' // More cost-effective for production
  },

  // Enable monitoring in production
  enableMonitoring: process.env.NODE_ENV === 'production',

  // Limit conversation history to prevent memory issues
  maxHistorySize: 20
};

// Error reporting for production
class ProductionErrorReporter {
  static report(error: Error, context?: any) {
    if (process.env.NODE_ENV === 'production') {
      // Send to monitoring service (e.g., Sentry, LogRocket)
      console.error('Production error:', error, context);

      // Example: Send to analytics
      if (typeof gtag !== 'undefined') {
        gtag('event', 'exception', {
          description: error.message,
          fatal: false
        });
      }
    } else {
      console.error('Development error:', error, context);
    }
  }
}
```

#### Performance Monitoring

```typescript
// Production performance monitoring
class PerformanceTracker {
  private static instance: PerformanceTracker;
  private metrics: Map<string, number[]> = new Map();

  static getInstance() {
    if (!PerformanceTracker.instance) {
      PerformanceTracker.instance = new PerformanceTracker();
    }
    return PerformanceTracker.instance;
  }

  recordMetric(name: string, value: number) {
    if (!this.metrics.has(name)) {
      this.metrics.set(name, []);
    }

    const values = this.metrics.get(name)!;
    values.push(value);

    // Keep only recent values
    if (values.length > 100) {
      values.shift();
    }

    // Send to analytics periodically
    if (values.length % 10 === 0) {
      this.sendAnalytics(name, values);
    }
  }

  private sendAnalytics(name: string, values: number[]) {
    if (process.env.NODE_ENV !== 'production') return;

    const avg = values.reduce((a, b) => a + b, 0) / values.length;
    const min = Math.min(...values);
    const max = Math.max(...values);

    // Send to your analytics service
    console.log(`Performance metric: ${name}`, { avg, min, max });
  }

  // Track voice pipeline performance
  trackPipelineLatency(stage: string, latency: number) {
    this.recordMetric(`pipeline_${stage}_latency`, latency);

    // Alert on high latency
    if (latency > 2000) { // 2 seconds
      console.warn(`High latency detected for ${stage}: ${latency}ms`);
    }
  }
}

// Usage in pipeline
const performanceTracker = PerformanceTracker.getInstance();

// Track transcription latency
pipeline.on('transcription', (result) => {
  performanceTracker.trackPipelineLatency('transcription', result.latency);
});

// Track LLM response latency
pipeline.on('llmResponse', (result) => {
  performanceTracker.trackPipelineLatency('llm', result.latency);
});
```

This comprehensive guide provides everything developers need to successfully integrate and use the RunAnywhere Web Voice SDK in their applications. The examples cover common use cases and the troubleshooting section addresses typical issues encountered in production deployments.
