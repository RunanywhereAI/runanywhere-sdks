# RunAnywhere Web Voice SDK

A modern, TypeScript-first web SDK for voice AI pipelines that run directly in the browser. Built with latest web standards and optimized for performance.

## 🚀 Phase 1 Complete

This implementation completes Phase 1 of the web voice pipeline, establishing:

- ✅ **Monorepo Structure** with PNPM workspaces
- ✅ **Core Package** with Result types, error handling, logging, and DI
- ✅ **Voice Package** with VAD service and pipeline manager
- ✅ **Demo Application** with real-time visualization
- ✅ **Modern TypeScript** with strict mode and latest patterns
- ✅ **Build System** with Vite 6.x

## 📦 Project Structure

```
sdk/runanywhere-web/
├── packages/
│   ├── core/          # Foundation utilities
│   │   ├── src/
│   │   │   ├── types/       # Result types, branded types
│   │   │   ├── errors/      # Error system
│   │   │   ├── utils/       # Logger
│   │   │   └── di/          # Dependency injection
│   │   └── package.json
│   │
│   └── voice/         # Voice processing
│       ├── src/
│       │   ├── services/    # VAD service
│       │   └── pipeline/    # Pipeline manager
│       └── package.json
│
├── examples/
│   └── vanilla/       # Demo application
│       ├── src/
│       ├── index.html
│       └── package.json
│
└── pnpm-workspace.yaml
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

```bash
# Clone the repository
cd sdk/runanywhere-web

# Install dependencies
pnpm install

# Build all packages
pnpm build
```

### Running the Demo

```bash
# Start the demo application
cd examples/vanilla
pnpm dev

# Opens at http://localhost:5173
```

## 💻 Usage

### Basic Pipeline Setup

```typescript
import { VoicePipelineManager } from '@runanywhere/voice';
import { logger, LogLevel } from '@runanywhere/core';

// Configure logging
logger.setLevel(LogLevel.DEBUG);

// Create pipeline
const pipeline = new VoicePipelineManager({
  vad: {
    enabled: true,
    config: {
      positiveSpeechThreshold: 0.9,
      negativeSpeechThreshold: 0.75,
      minSpeechFrames: 5,
      frameSamples: 1536
    }
  }
});

// Handle events
pipeline.on('event', (event) => {
  switch (event.type) {
    case 'vad:speech_start':
      console.log('Speech detected!');
      break;
    case 'vad:speech_end':
      console.log('Speech ended, duration:', event.duration);
      break;
  }
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

### Phase 1 (Completed) ✅
- Voice Activity Detection (VAD)
- Pipeline orchestration
- Event-driven architecture
- Real-time metrics
- Health monitoring
- Demo application

### Phase 2 (Upcoming) 🔜
- Speech-to-Text (STT) with Transformers.js
- Model management
- Web Workers integration
- Audio processing utilities
- React integration package

### Phase 3 (Future) 📅
- Text-to-Speech (TTS) with ONNX Runtime
- LLM integration
- Streaming responses
- Advanced audio features
- Vue/Angular integrations

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

**Phase 1 Status**: ✅ Complete
**Next**: Phase 2 - STT Integration with Transformers.js
