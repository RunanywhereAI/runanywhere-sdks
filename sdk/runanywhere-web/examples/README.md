# RunAnywhere Web SDK Examples

This directory contains example applications demonstrating how to use the RunAnywhere Web SDK with different frameworks.

## Available Examples

### 🟢 Vue 3 Example
- **Location**: `vue-example/`
- **Port**: http://localhost:5174
- **Features**: Vue 3 with Composition API, TypeScript, Vite

```bash
cd vue-example
pnpm install
pnpm dev
```

### 🔴 Angular Example
- **Location**: `angular-example/`
- **Port**: http://localhost:5175
- **Features**: Angular 17 with standalone components, TypeScript, RxJS

```bash
cd angular-example
pnpm install
pnpm serve
```

### ⚪ Vanilla JavaScript Example
- **Location**: `vanilla/`
- **Port**: http://localhost:5173
- **Features**: Pure TypeScript/JavaScript with Vite

```bash
cd vanilla
pnpm install
pnpm dev
```

## Example Features

Each example demonstrates:

- ✅ **Voice Pipeline Integration** - Complete STT → LLM → TTS pipeline
- ✅ **Real-time Conversation** - Live conversation history with timestamps
- ✅ **Performance Metrics** - VAD, STT, LLM, and TTS latency tracking
- ✅ **Error Handling** - Proper error states and recovery
- ✅ **Modern UI** - Clean, responsive design with status indicators
- ✅ **TypeScript Support** - Full type safety and IntelliSense

## Getting Started

1. **Install dependencies** (from the root workspace):
   ```bash
   cd ../
   pnpm install
   ```

2. **Build all packages**:
   ```bash
   pnpm build
   ```

3. **Run an example**:
   ```bash
   cd examples/vue-example    # or angular-example
   pnpm dev                   # or pnpm serve for Angular
   ```

## Framework Integration Patterns

### React (hooks + components)
```tsx
import { useVoicePipeline, VoiceChat } from '@runanywhere/react';

const [state, actions] = useVoicePipeline(config);
```

### Vue 3 (composables + components)
```vue
<script setup>
import { useVoicePipeline, VoiceChat } from '@runanywhere/vue';

const { state, initialize, start } = useVoicePipeline(config);
</script>
```

### Angular (services + components)
```typescript
import { VoicePipelineService } from '@runanywhere/angular';

constructor(private voiceService: VoicePipelineService) {}
```

## Configuration

All examples use the same voice pipeline configuration:

```typescript
const config = {
  enableTranscription: true,  // Speech-to-text
  enableLLM: true,           // Language model processing
  enableTTS: true,           // Text-to-speech
  autoPlayTTS: true,         // Auto-play generated speech
  maxHistorySize: 50         // Conversation history limit
};
```

## Troubleshooting

### Build Issues
If you encounter build issues, try:
```bash
# From workspace root
pnpm clean
pnpm install
pnpm build
```

### Development Server Issues
Each example runs on a different port to avoid conflicts:
- Vue: `:5174`
- Angular: `:5175`
- Vanilla: `:5173`

### Browser Permissions
Make sure to allow microphone access when prompted. The voice pipeline requires microphone permissions to capture audio input.

## Learn More

- [Framework Integration Guide](../README.md#-usage)
- [Voice Pipeline Documentation](../packages/voice/README.md)
- [Core SDK Documentation](../packages/core/README.md)
