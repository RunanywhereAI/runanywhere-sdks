# @runanywhere/vad-silero

Production-ready Silero VAD adapter using @ricky0123/vad-web for accurate voice activity detection.

## Features

- ✅ **Real Silero VAD**: Uses actual Silero VAD v5 model via @ricky0123/vad-web
- ✅ **Self-Contained**: No external files needed - everything is handled internally
- ✅ **Event-Based API**: Simple event emitters for speech start/end detection
- ✅ **Audio Capture**: Provides actual speech audio as Float32Array
- ✅ **Metrics Tracking**: Built-in metrics for speech duration and detection counts
- ✅ **TypeScript Support**: Full type definitions included

## Quick Start

```bash
npm install @runanywhere/vad-silero
```

```typescript
import { SileroVADAdapter } from '@runanywhere/vad-silero';

// Create and use VAD
const vad = new SileroVADAdapter();

// Set up events
vad.on('speech_start', () => console.log('🎤 Speaking...'));
vad.on('speech_end', (audio) => console.log('🔇 Speech ended:', audio.length, 'samples'));

// Initialize and start (no setup needed!)
await vad.initialize();
await vad.start();
```

## React Hook (Recommended)

```typescript
import { useVADAdapter } from '@runanywhere/vad-silero';

function MyComponent() {
  const vad = useVADAdapter({
    positiveSpeechThreshold: 0.9,
    negativeSpeechThreshold: 0.75,
  });

  return (
    <div>
      <p>Status: {vad.isInitialized ? '✅ Ready' : '⏳ Loading'}</p>
      <p>Listening: {vad.isListening ? '🎤' : '🔇'}</p>
      <p>Speaking: {vad.isSpeaking ? '🗣️' : '😶'}</p>

      {!vad.isInitialized && (
        <button onClick={vad.initialize}>Initialize</button>
      )}

      {vad.isInitialized && !vad.isListening && (
        <button onClick={vad.startListening}>Start Listening</button>
      )}

      {vad.isListening && (
        <button onClick={vad.stopListening}>Stop</button>
      )}

      {vad.speechAudio && (
        <p>✅ Captured: {vad.speechAudio.length} samples</p>
      )}
    </div>
  );
}
```

## Configuration

```typescript
interface SileroVADConfig {
  // Silero model version
  model?: 'v5' | 'legacy';                    // Default: 'v5'

  // CDN paths (optional - uses defaults)
  baseAssetPath?: string;
  onnxWASMBasePath?: string;

  // Detection sensitivity
  positiveSpeechThreshold?: number;           // 0-1, default: 0.9
  negativeSpeechThreshold?: number;           // 0-1, default: 0.75
  minSpeechDuration?: number;                 // ms, default: 96
  preSpeechPadding?: number;                  // ms, default: 320
}
```

## API Reference

### Initialization

```typescript
// Basic initialization
await vad.initialize();

// With custom config
await vad.initialize({
  positiveSpeechThreshold: 0.85,  // More sensitive
  model: 'v5',
  minSpeechDuration: 200
});
```

### Control Methods

```typescript
await vad.start();        // Start listening
vad.stop();              // Stop listening
vad.pause();             // Pause (keeps mic active)
vad.resume();            // Resume from pause
vad.destroy();           // Clean up resources
```

### Events

```typescript
vad.on('speech_start', () => {
  // User started speaking
});

vad.on('speech_end', (audio: Float32Array) => {
  // User stopped speaking
  // audio is 16kHz mono Float32Array
  console.log(`Duration: ${(audio.length / 16000).toFixed(2)}s`);
});

vad.on('vad_misfire', () => {
  // False positive detection
});
```

### Metrics

```typescript
const metrics = vad.getMetrics();
console.log({
  totalDetections: metrics.totalDetections,
  avgDuration: metrics.avgSpeechDuration,
  totalSpeechTime: metrics.totalSpeechMs
});
```

## Advanced Usage

### Integration with STT

```typescript
vad.on('speech_end', async (audio: Float32Array) => {
  // Send to speech-to-text service
  const transcript = await speechToText(audio);
  console.log('Said:', transcript);
});
```

### Performance Tuning

```typescript
// More sensitive (detects quieter speech)
await vad.initialize({
  positiveSpeechThreshold: 0.8,
  negativeSpeechThreshold: 0.6
});

// Less sensitive (ignores background noise)
await vad.initialize({
  positiveSpeechThreshold: 0.95,
  negativeSpeechThreshold: 0.85
});
```

### Custom CDN

```typescript
await vad.initialize({
  baseAssetPath: 'https://your-cdn.com/vad-models/',
  onnxWASMBasePath: 'https://your-cdn.com/onnx-runtime/'
});
```

## How It Works

1. **Model Loading**: Downloads Silero VAD v5 model (~2MB) from CDN
2. **Audio Capture**: Requests microphone and processes 16kHz audio
3. **Real-time VAD**: Runs Silero neural network on audio frames
4. **Event Emission**: Fires events with actual captured speech audio
5. **Resource Management**: Automatic cleanup and memory management

## Bundle Size

- **Package**: ~5KB (ESM) / ~4KB (CJS)
- **Runtime**: @ricky0123/vad-web loaded on-demand
- **Model**: ~2MB (cached after first load)

## Browser Support

- ✅ Chrome 66+
- ✅ Firefox 60+
- ✅ Safari 12+
- ✅ Edge 79+

**Requirements**: `getUserMedia`, `AudioContext`, `AudioWorklet`

## Troubleshooting

**Microphone Permission**
```typescript
const result = await vad.start();
if (!result.success) {
  console.log('Microphone access required');
}
```

**Not Detecting Speech**
```typescript
// Try lower thresholds
await vad.initialize({
  positiveSpeechThreshold: 0.8,
  negativeSpeechThreshold: 0.6
});
```

**Model Loading Issues**
- Check network connectivity
- Models load from jsdelivr CDN by default
- Verify no content blockers interfering

## License

MIT
