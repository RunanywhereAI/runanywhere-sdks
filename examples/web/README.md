# RunAnywhere Web Examples

This directory contains complete web application examples demonstrating the RunAnywhere Voice SDK across different frameworks.

## Available Examples

### React Demo (`react-demo/`)
A comprehensive React application showcasing the complete voice pipeline with:
- Ultra-low latency voice processing (VAD → STT → LLM → TTS)
- Real-time performance monitoring dashboard
- Professional UI with configuration panel
- TypeScript + Tailwind CSS + Vite

**Quick Start:**
```bash
cd react-demo
pnpm install
pnpm dev
```

### Vue Demo (`vue-demo/`)
Vue.js implementation of voice features:
- Basic voice pipeline integration
- Vue composition API usage
- Vite build system

**Quick Start:**
```bash
cd vue-demo
pnpm install
pnpm dev
```

### Angular Demo (`angular-demo/`)
Angular implementation demonstrating:
- Angular service architecture
- Voice SDK integration patterns
- TypeScript integration

**Quick Start:**
```bash
cd angular-demo
pnpm install
ng serve
```

## Common Prerequisites

- Node.js 18+
- pnpm (recommended) or npm
- OpenAI API key (for LLM functionality)
- Modern browser with:
  - WebAssembly support
  - Web Audio API
  - getUserMedia support

## Development

### Running from Root
You can run any example from the repository root:

```bash
# React demo
pnpm --filter react-voice-demo dev

# Vue demo
pnpm --filter vue-voice-demo dev

# Angular demo
pnpm --filter angular-voice-demo serve
```

### Building for Production
```bash
# React demo
pnpm --filter react-voice-demo build

# Vue demo
pnpm --filter vue-voice-demo build

# Angular demo
pnpm --filter angular-voice-demo build
```

## SDK Package Dependencies

All examples depend on these workspace packages:
- `@runanywhere/core` - Core utilities and DI container
- `@runanywhere/voice` - Voice pipeline management
- `@runanywhere/react` - React hooks and components (React only)
- `@runanywhere/transcription` - Speech-to-text services
- `@runanywhere/tts` - Text-to-speech services
- `@runanywhere/llm` - Language model integration
- `@runanywhere/cache` - Model and response caching
- `@runanywhere/monitoring` - Performance monitoring
- `@runanywhere/workers` - Web Worker utilities

## Browser Compatibility

### Minimum Requirements
- Chrome 90+, Firefox 90+, Safari 15+, Edge 90+
- WebAssembly support
- SharedArrayBuffer support (for ONNX models)
- Secure context (HTTPS) for microphone access

### Performance Recommendations
- Use Chrome for best WebAssembly performance
- Enable hardware acceleration
- Ensure stable internet connection for cloud LLM calls

## Troubleshooting

### Common Issues

**SharedArrayBuffer errors:**
Add these headers to your development server:
```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

**Microphone not working:**
- Grant microphone permissions
- Use HTTPS in production
- Check browser security settings

**High memory usage:**
- Use smaller models (Whisper Tiny)
- Enable model caching
- Monitor browser memory usage

### Development Tips

1. **Hot Reload**: All examples support hot reload during development
2. **TypeScript**: Strict TypeScript checking enabled for better developer experience
3. **Linting**: ESLint configured for code quality
4. **Performance**: Built-in performance monitoring in React demo

## Contributing

When adding new examples:

1. Create a new directory under `examples/web/`
2. Follow the existing naming convention (`framework-demo`)
3. Include a comprehensive README
4. Add to the workspace configuration
5. Ensure TypeScript strict mode
6. Include error handling and loading states
7. Document performance characteristics

## License

These examples are part of the RunAnywhere SDK project. See the root LICENSE file for details.
