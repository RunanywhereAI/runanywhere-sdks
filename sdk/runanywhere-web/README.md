# RunAnywhere Web Voice SDK

A comprehensive, TypeScript-first web SDK for complete voice AI pipelines that run directly in the browser. Features framework adapters for React, Vue, and Angular with full speech-to-text, LLM, and text-to-speech capabilities.

## 🚀 Phase 5 Complete - Framework Integration

This implementation completes Phase 5 of the web voice pipeline, establishing a **complete voice AI ecosystem**:

- ✅ **Complete Voice Pipeline** with STT, LLM, and TTS
- ✅ **Framework Adapters** for React, Vue 3, and Angular
- ✅ **Monorepo Structure** with PNPM workspaces
- ✅ **13 Specialized Packages** with modular architecture
- ✅ **Production Ready** components and services
- ✅ **Full TypeScript** support with strict mode
- ✅ **Modern Build System** with Vite and optimizations

## 📦 Project Structure

```
sdk/runanywhere-web/
├── packages/
│   ├── core/              # Foundation utilities & DI container
│   ├── voice/             # Complete voice pipeline manager
│   ├── transcription/     # Speech-to-text services
│   ├── llm/               # Large language model integration
│   ├── tts/               # Text-to-speech services
│   ├── cache/             # Caching strategies & persistence
│   ├── monitoring/        # Performance tracking & analytics
│   ├── optimization/      # Resource optimization & batching
│   ├── workers/           # Web Workers for heavy processing
│   │
│   └── framework-adapters/
│       ├── react/         # React hooks & components
│       ├── vue/           # Vue 3 composables & components
│       └── angular/       # Angular services & components
│
├── examples/
│   └── vanilla/           # Demo application
│
├── scripts/               # Build & development scripts
└── pnpm-workspace.yaml    # Workspace configuration
```

## 🛠️ Technology Stack

- **TypeScript 5.7.2** - Latest TypeScript with strict mode
- **Vite 6.0.3** - Next-gen build tool
- **PNPM 9.x** - Fast, disk space efficient package manager
- **@ricky0123/vad-web** - Voice Activity Detection
- **EventEmitter3** - High-performance event emitter
- **Vitest 2.1.8** - Modern testing framework

## 🚦 Quick Start

### Prerequisites

- Node.js >= 20.0.0
- PNPM >= 9.0.0

### Installation

#### From Source (Development)

```bash
# Clone the repository
cd sdk/runanywhere-web

# Install dependencies
pnpm install

# Build all packages
pnpm build
```

#### Framework-Specific Packages

```bash
# React
npm install @runanywhere/react @runanywhere/core @runanywhere/voice

# Vue 3
npm install @runanywhere/vue @runanywhere/core @runanywhere/voice

# Angular
npm install @runanywhere/angular @runanywhere/core @runanywhere/voice

# Core only (vanilla JavaScript)
npm install @runanywhere/voice @runanywhere/core
```

### Running the Demo

```bash
# Start the demo application
cd examples/vanilla
pnpm dev

# Opens at http://localhost:5173
```

## 💻 Usage

### React Integration

```tsx
import { useVoicePipeline } from '@runanywhere/react';
import { VoiceChat, VoicePipelineButton } from '@runanywhere/react';

function VoiceApp() {
  const [state, actions] = useVoicePipeline({
    enableTranscription: true,
    enableLLM: true,
    enableTTS: true,
    autoPlayTTS: true
  });

  return (
    <div>
      <h1>Voice AI Assistant</h1>
      <VoicePipelineButton
        config={{ enableTranscription: true, enableLLM: true }}
        onTranscription={(result) => console.log('User said:', result.text)}
        onLLMResponse={(result) => console.log('AI replied:', result.text)}
      />
      <VoiceChat
        config={{ enableTranscription: true, enableLLM: true }}
        className="voice-chat"
      />
    </div>
  );
}
```

### Vue 3 Integration

```vue
<template>
  <div>
    <h1>Voice AI Assistant</h1>
    <VoicePipelineButton
      :config="{ enableTranscription: true, enableLLM: true }"
      @transcription="handleTranscription"
      @llm-response="handleLLMResponse"
    />
    <VoiceChat
      :config="{ enableTranscription: true, enableLLM: true }"
      class="voice-chat"
    />
    <div v-if="!isReady" class="error">{{ state.error?.message }}</div>
  </div>
</template>

<script setup lang="ts">
import { useVoicePipeline, VoiceChat, VoicePipelineButton } from '@runanywhere/vue';

const { state, isReady, initialize, start, stop } = useVoicePipeline({
  enableTranscription: true,
  enableLLM: true,
  enableTTS: true,
  autoInitialize: true
});

const handleTranscription = (result) => {
  console.log('User said:', result.text);
};

const handleLLMResponse = (result) => {
  console.log('AI replied:', result.text);
};
</script>
```

### Angular Integration

```typescript
// app.module.ts
import { NgModule } from '@angular/core';
import { BrowserModule } from '@angular/common';
import { RunAnywhereVoiceModule } from '@runanywhere/angular';
import { AppComponent } from './app.component';

@NgModule({
  declarations: [AppComponent],
  imports: [
    BrowserModule,
    RunAnywhereVoiceModule
  ],
  providers: [],
  bootstrap: [AppComponent]
})
export class AppModule { }
```

```typescript
// app.component.ts
import { Component, OnInit } from '@angular/core';
import { VoicePipelineService } from '@runanywhere/angular';

@Component({
  selector: 'app-root',
  template: `
    <h1>Voice AI Assistant</h1>
    <runanywhere-voice-pipeline-button
      [config]="config"
      (transcription)="handleTranscription($event)"
      (llmResponse)="handleLLMResponse($event)">
    </runanywhere-voice-pipeline-button>

    <runanywhere-voice-chat
      [config]="config"
      class="voice-chat">
    </runanywhere-voice-chat>

    <div *ngIf="!isReady" class="error">{{ error?.message }}</div>
  `
})
export class AppComponent implements OnInit {
  config = {
    enableTranscription: true,
    enableLLM: true,
    enableTTS: true
  };

  constructor(public voiceService: VoicePipelineService) {}

  async ngOnInit() {
    await this.voiceService.initialize(this.config);
  }

  get isReady() {
    return this.voiceService.isReady$.pipe(tap(ready => console.log('Ready:', ready)));
  }

  get error() {
    return this.voiceService.currentState.error;
  }

  handleTranscription(result: any) {
    console.log('User said:', result.text);
  }

  handleLLMResponse(result: any) {
    console.log('AI replied:', result.text);
  }
}
```

### Vanilla JavaScript (Core Pipeline)

```typescript
import { EnhancedVoicePipelineManager } from '@runanywhere/voice';
import { DIContainer } from '@runanywhere/core';

// Create DI container and pipeline
const container = new DIContainer();
const pipeline = new EnhancedVoicePipelineManager(container, {
  enableTranscription: true,
  enableLLM: true,
  enableTTS: true,
  autoPlayTTS: true
});

// Handle events
pipeline.on('transcription', (result) => {
  console.log('User said:', result.text);
});

pipeline.on('llmResponse', (result) => {
  console.log('AI replied:', result.text);
});

pipeline.on('ttsComplete', (result) => {
  console.log('TTS audio ready');
});

// Initialize and start
await pipeline.initialize();
await pipeline.start();
```

### Using Dependency Injection

```typescript
import { DIContainer, ServiceToken } from '@runanywhere/core';
import { WebVADService, VAD_SERVICE_TOKEN } from '@runanywhere/voice';

const container = new DIContainer();

// Register service
container.register(VAD_SERVICE_TOKEN, {
  factory: async () => {
    const vad = new WebVADService();
    await vad.initialize();
    return vad;
  },
  lifecycle: 'singleton',
  healthCheck: async () => vad.isHealthy()
});

// Resolve service
const vad = await container.resolve<WebVADService>(VAD_SERVICE_TOKEN);
```

## 🏗️ Architecture

### Core Package

- **Result Type**: Functional error handling without exceptions
- **Branded Types**: Type-safe IDs (SessionId, PipelineId, etc.)
- **Error System**: Hierarchical error classes with context
- **Logger**: Configurable logging with handlers
- **DI Container**: Modern dependency injection with Symbol tokens

### Voice Package

- **VAD Service**: Voice Activity Detection with @ricky0123/vad-web
- **Pipeline Manager**: Orchestrates voice processing components
- **Event System**: Type-safe event handling with discriminated unions
- **Metrics**: Real-time performance tracking
- **Health Monitoring**: Component health checks

## 📊 Key Features

### Complete Voice AI Pipeline ✅
- **Voice Activity Detection (VAD)** with @ricky0123/vad-web
- **Speech-to-Text (STT)** with Transformers.js
- **Large Language Model (LLM)** integration
- **Text-to-Speech (TTS)** with Web Speech API & ONNX Runtime
- **End-to-end pipeline** from audio input to audio output

### Framework Integration ✅
- **React Hooks & Components** - `useVoicePipeline`, `VoiceChat`, `VoicePipelineButton`
- **Vue 3 Composables & Components** - `useVoicePipeline`, `VoiceChat`, `VoicePipelineButton`
- **Angular Services & Components** - `VoicePipelineService`, `VoiceChatComponent`, `VoicePipelineButtonComponent`
- **TypeScript Support** - Full type safety across all frameworks

### Performance & Optimization ✅
- **Web Workers** for heavy processing tasks
- **Caching System** for models and responses
- **Performance Monitoring** with real-time metrics
- **Resource Optimization** with batching and lazy loading
- **Memory Management** with automatic cleanup

### Production Features ✅
- **Dependency Injection** with modern DI container
- **Error Handling** with Result types and proper boundaries
- **Event System** with type-safe event handling
- **Health Monitoring** for all services
- **Logging System** with configurable levels

## 🧪 Testing

```bash
# Run all tests
pnpm test

# Run with coverage
pnpm test -- --coverage

# Watch mode
pnpm test -- --watch
```

## 📝 Scripts

```bash
# Development
pnpm dev          # Start dev servers
pnpm build        # Build all packages
pnpm test         # Run tests
pnpm typecheck    # Type checking
pnpm lint         # Lint code
pnpm format       # Format code
pnpm clean        # Clean build artifacts
```

## 🔧 Configuration

### TypeScript Configuration

The project uses strict TypeScript configuration with:
- `strict: true`
- `noUncheckedIndexedAccess: true`
- `noImplicitOverride: true`
- Target: ES2022
- Module: ESNext

### Build Configuration

Vite is configured for:
- ES2020 target
- Source maps enabled
- Library mode for packages
- Optimized chunking

## 🤝 Contributing

1. Follow the existing code patterns
2. Use TypeScript strict mode
3. Write tests for new features
4. Update documentation
5. Run `pnpm format` before committing

## 📄 License

[License Information]

## 🙏 Acknowledgments

- iOS SDK architecture for design inspiration
- @ricky0123/vad-web for VAD implementation
- Modern web standards and best practices

## 📞 Support

For issues or questions, please file an issue in the repository.

---

**Phase 5 Status**: ✅ Complete - Framework Integration
**Current**: Production-ready voice AI SDK with React, Vue, and Angular support
**Next**: Advanced features - Multi-language support, streaming optimizations
