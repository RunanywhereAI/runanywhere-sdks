# RunAnywhere SDK Examples

This directory contains example applications demonstrating how to use the RunAnywhere SDK across different platforms and frameworks.

## Structure

```
examples/
├── android/           # Android example apps
├── ios/              # iOS example apps
└── web/              # Web framework examples
    ├── react-demo/   # React demo application
    ├── vue-demo/     # Vue.js demo application
    └── angular-demo/ # Angular demo application
```

## Web Examples

### 🔵 React Demo (Recommended)
**Location**: `web/react-demo/`

A comprehensive React application showcasing the complete RunAnywhere Voice SDK with:
- Ultra-low latency voice processing (VAD → STT → LLM → TTS)
- Real-time performance monitoring dashboard
- Professional UI with configuration panel
- TypeScript + Tailwind CSS + Vite

```bash
cd web/react-demo
pnpm install
pnpm dev
# → http://localhost:5173
```

### 🟢 Vue Demo
**Location**: `web/vue-demo/`

Vue.js implementation with Composition API:
- Voice pipeline integration
- Vue-style reactivity
- TypeScript support

```bash
cd web/vue-demo
pnpm install
pnpm dev
# → http://localhost:5174
```

### 🔴 Angular Demo
**Location**: `web/angular-demo/`

Angular implementation with:
- Service-based architecture
- Dependency injection patterns
- RxJS integration

```bash
cd web/angular-demo
pnpm install
pnpm dev
# → http://localhost:5175
```

## Prerequisites

- **Node.js** 18+
- **pnpm** (recommended package manager)
- **OpenAI API key** (for LLM functionality)
- **Modern browser** with WebAssembly support

## Quick Start

### From Repository Root
```bash
# Install all dependencies (includes examples)
cd sdk/runanywhere-web
pnpm install

# Build all SDK packages
pnpm build

# Run specific example
pnpm --filter react-voice-demo dev
```

### From Examples Directory
```bash
# Navigate to desired example
cd web/react-demo

# Install dependencies
pnpm install

# Start development server
pnpm dev
```

## SDK Integration

All web examples demonstrate integration with the RunAnywhere Web SDK packages:

- `@runanywhere/core` - Core utilities and DI container
- `@runanywhere/voice` - Voice pipeline management
- `@runanywhere/react` - React hooks and components
- `@runanywhere/transcription` - Speech-to-text services
- `@runanywhere/tts` - Text-to-speech services
- `@runanywhere/llm` - Language model integration
- `@runanywhere/cache` - Model and response caching
- `@runanywhere/monitoring` - Performance monitoring
- `@runanywhere/workers` - Web Worker utilities

## Platform Examples

### Android Examples
Located in `android/RunAnywhereAI/` - demonstrates native Android integration with the RunAnywhere SDK.

### iOS Examples
Located in `ios/RunAnywhereAI/` - demonstrates native iOS integration with SwiftUI and the RunAnywhere Swift SDK.

## Documentation

- [Web Examples Guide](web/README.md)
- [React Demo Documentation](web/react-demo/README.md)
- [SDK Documentation](../sdk/runanywhere-web/README.md)

## Contributing

When adding new examples:

1. Follow the established directory structure
2. Include comprehensive README documentation
3. Add appropriate .gitignore files
4. Use TypeScript for type safety
5. Include error handling and loading states
6. Document performance characteristics
7. Add to workspace configuration if needed

## License

These examples are part of the RunAnywhere SDK project. See the root LICENSE file for details.
