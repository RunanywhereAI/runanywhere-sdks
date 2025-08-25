# Speech-to-Text Solution Analysis: Transformers.js vs Whisper-Web

## Executive Summary

After analyzing both `@huggingface/transformers` (v3.7.2) and `whisper-web` implementations, **we recommend using `whisper-web`'s architecture as a reference** while implementing our own solution using the latest `@huggingface/transformers` directly. This approach gives us the best of both worlds: the proven patterns from whisper-web with the flexibility to customize for our SDK needs.

## UPDATE: Current Implementation Issues and Fixes (2025-08-25)

### Critical Issue Identified: ONNX Runtime Error
**Error**: `invalid data location: undefined for input "a"`

This error occurs during transcription when the ONNX runtime attempts to process audio data. After detailed analysis of whisper-web's working implementation, we've identified several critical missing parameters and configuration issues.

### Key Differences Found in Whisper-Web

1. **Critical Pipeline Parameters Missing in Our Implementation**:
   ```javascript
   // MISSING - These are REQUIRED for proper ONNX inference
   top_k: 0,              // Forces greedy decoding
   do_sample: false,      // Disables sampling
   force_full_sequences: false  // Prevents sequence truncation issues
   ```

2. **Pipeline Factory Configuration Issue**:
   ```javascript
   // Whisper-web passes dtype and device during pipeline creation
   this.instance = await pipeline(this.task, this.model, {
       dtype: this.dtype,
       device: this.gpu ? "webgpu" : "wasm",
       progress_callback
   });

   // Our implementation is missing these parameters
   ```

3. **Audio Format Requirements**:
   - Must be Float32Array (not regular Array)
   - Sample rate: 16000 Hz
   - Mono channel (stereo needs conversion)

### Immediate Fixes Required

#### Fix 1: Update Worker Pipeline Call
```typescript
// In stt.worker.ts - Add missing critical parameters
const output = await pipelineInstance(audio, {
    // CRITICAL: Add these for ONNX to work
    top_k: 0,
    do_sample: false,

    // Sliding window
    chunk_length_s: 30,
    stride_length_s: 5,

    // Language and task
    language: data.language || null,
    task: data.task || 'transcribe',

    // Timestamps
    return_timestamps: true,
    force_full_sequences: false  // CRITICAL: Prevents ONNX errors
});
```

#### Fix 2: Update Pipeline Factory
```typescript
// In PipelineFactory.getInstance()
static async getInstance(progress_callback: any = null) {
    if (this.instance === null) {
        this.instance = await pipeline(this.task, this.model!, {
            dtype: 'q8',  // Simplified dtype like whisper-web
            device: 'wasm',  // Explicit device specification
            progress_callback,
        } as any);
    }
    return this.instance;
}
```

#### Fix 3: Ensure Proper Audio Format
```typescript
// Audio must be Float32Array, not Array
// Already fixed in latest implementation
```

---

## 1. Transformers.js Analysis (Original)

### Overview
- **Package**: `@huggingface/transformers` (formerly `@xenova/transformers`)
- **Version**: 3.7.2
- **Type**: Core ML library for browser-based inference
- **License**: Apache-2.0

### Key Features
1. **WebGPU Acceleration**: First-class support with automatic WASM fallback
2. **Model Variety**: Extensive Whisper model collection (tiny to large-v3-turbo)
3. **Streaming Support**: Real-time transcription with `TextStreamer`
4. **Quantization**: Multiple options (fp32, fp16, q8, q4) for size/speed tradeoffs
5. **CDN Loading**: Direct model loading from Hugging Face Hub

### Implementation Example
```javascript
import { pipeline } from '@huggingface/transformers';

// Create pipeline
const transcriber = await pipeline(
  'automatic-speech-recognition',
  'Xenova/whisper-tiny.en',
  {
    dtype: { encoder_model: 'fp32', decoder_model_merged: 'q4' },
    device: 'webgpu' // or 'wasm'
  }
);

// Transcribe
const result = await transcriber(audioData, {
  return_timestamps: true,
  chunk_length_s: 30,
  stride_length_s: 5
});
```

### Pros
- Direct control over model loading and configuration
- Lightweight integration (just the ML library)
- Extensive documentation and examples
- Active development and support

### Cons
- Requires implementing audio processing, UI, and state management
- Manual worker setup needed for non-blocking operation
- No built-in caching management UI

---

## 2. Whisper-Web Analysis

### Overview
- **Type**: Complete web application with React
- **Dependencies**: Uses `@huggingface/transformers` v3.7.0
- **Architecture**: Web Worker-based with React hooks
- **Features**: Full UI, PWA support, multiple export formats

### Architecture Highlights
1. **Web Worker Pattern**: Offloads ML to background thread
2. **PipelineFactory**: Singleton pattern for model management
3. **React Hooks**: `useTranscriber` for state management
4. **Progressive Loading**: Real-time download progress
5. **Smart Defaults**: Auto model selection based on device

### Key Components
```javascript
// Worker setup (worker.js)
class PipelineFactory {
  static async getInstance(progressCallback) {
    // Singleton pattern for model management
    if (!this.instance) {
      this.instance = await pipeline('automatic-speech-recognition', ...);
    }
    return this.instance;
  }
}

// React hook (useTranscriber.js)
function useTranscriber() {
  const [transcript, setTranscript] = useState([]);
  const [isLoading, setIsLoading] = useState(false);
  // ... state management and worker communication
}
```

### Pros
- Production-ready solution with complete UX
- Proven patterns for browser-based ML
- Excellent audio handling and format support
- PWA with offline capabilities
- Multi-language UI support

### Cons
- Full React application (not a library/SDK)
- Opinionated architecture
- Harder to integrate into existing applications
- Includes UI components we don't need

---

## 3. Recommendation for RunAnywhere SDK

### Recommended Approach: **Hybrid Solution**

Use **whisper-web's architecture patterns** while implementing with **@huggingface/transformers directly**.

### Implementation Strategy

#### 1. **Update Dependencies**
```json
{
  "dependencies": {
    "@huggingface/transformers": "^3.7.2"  // Update from @xenova/transformers
  }
}
```

#### 2. **Adopt Worker Architecture from Whisper-Web**
```typescript
// stt-whisper/src/worker.ts
import { pipeline, env } from '@huggingface/transformers';

class WhisperPipelineFactory {
  private static instance: any = null;

  static async getInstance(modelId: string, progressCallback?: Function) {
    if (!this.instance) {
      env.allowRemoteModels = true;
      env.remoteHost = 'https://huggingface.co/';
      env.useBrowserCache = true;

      this.instance = await pipeline(
        'automatic-speech-recognition',
        modelId,
        {
          dtype: {
            encoder_model: 'fp32',
            decoder_model_merged: 'q4'
          },
          device: navigator.gpu ? 'webgpu' : 'wasm',
          progress_callback: progressCallback
        }
      );
    }
    return this.instance;
  }

  static dispose() {
    if (this.instance) {
      this.instance.dispose();
      this.instance = null;
    }
  }
}
```

#### 3. **Improved WhisperSTTAdapter**
```typescript
export class WhisperSTTAdapter extends BaseAdapter<STTEvents> implements STTAdapter {
  private worker?: Worker;
  private pipeline?: any;

  async initialize(): Promise<Result<void, Error>> {
    try {
      // Create worker for non-blocking operation
      this.worker = new Worker(new URL('./worker.ts', import.meta.url), {
        type: 'module'
      });

      return Result.ok(undefined);
    } catch (error) {
      return Result.err(error as Error);
    }
  }

  async loadModel(modelId: string): Promise<Result<void, Error>> {
    return new Promise((resolve) => {
      this.worker?.postMessage({
        type: 'load',
        data: { model: modelId }
      });

      this.worker?.addEventListener('message', (e) => {
        if (e.data.type === 'loaded') {
          resolve(Result.ok(undefined));
        } else if (e.data.type === 'error') {
          resolve(Result.err(new Error(e.data.error)));
        } else if (e.data.type === 'progress') {
          this.emit('model_loading', e.data.progress);
        }
      });
    });
  }

  async transcribe(audio: Float32Array, options?: TranscribeOptions) {
    // Process audio in chunks like whisper-web
    const CHUNK_LENGTH = 30; // seconds
    const STRIDE_LENGTH = 5; // seconds

    return new Promise((resolve) => {
      this.worker?.postMessage({
        type: 'transcribe',
        data: {
          audio,
          options: {
            ...options,
            chunk_length_s: CHUNK_LENGTH,
            stride_length_s: STRIDE_LENGTH,
            return_timestamps: true
          }
        }
      });

      // Handle streaming results
      this.worker?.addEventListener('message', (e) => {
        if (e.data.type === 'result') {
          resolve(Result.ok(e.data.result));
        } else if (e.data.type === 'chunk') {
          this.emit('transcription_progress', e.data.chunk);
        }
      });
    });
  }
}
```

#### 4. **Audio Processing Utilities (from whisper-web)**
```typescript
// utils/audio.ts
export function processAudio(audioData: Float32Array[], sampleRate: number): Float32Array {
  // Convert to 16kHz mono as required by Whisper
  const targetSampleRate = 16000;

  // Convert stereo to mono if needed
  let audio = audioData;
  if (audio.length > 1) {
    const SCALING_FACTOR = Math.sqrt(2);
    audio = [new Float32Array(audio[0].length)];
    for (let i = 0; i < audio[0].length; ++i) {
      audio[0][i] = SCALING_FACTOR * (audioData[0][i] + audioData[1][i]) / 2;
    }
  }

  // Resample to 16kHz if needed
  if (sampleRate !== targetSampleRate) {
    // Implement resampling logic
  }

  return audio[0];
}
```

### Key Improvements to Implement

1. **WebGPU Detection and Fallback**
```typescript
const device = navigator.gpu ? 'webgpu' : 'wasm';
const dtype = device === 'webgpu'
  ? { encoder_model: 'fp32', decoder_model_merged: 'q4' }
  : { encoder_model: 'fp32', decoder_model_merged: 'q8' };
```

2. **Model Recommendations by Device**
```typescript
function getRecommendedModel(): string {
  const isMobile = /iPhone|iPad|Android/i.test(navigator.userAgent);
  const hasWebGPU = !!navigator.gpu;

  if (isMobile) {
    return 'Xenova/whisper-tiny.en'; // ~39MB
  } else if (hasWebGPU) {
    return 'Xenova/whisper-base'; // ~77MB, better accuracy
  } else {
    return 'Xenova/whisper-tiny.en'; // Fallback for WASM
  }
}
```

3. **Streaming Transcription Support**
```typescript
import { TextStreamer } from '@huggingface/transformers';

const streamer = new TextStreamer(tokenizer, {
  skip_prompt: true,
  skip_special_tokens: true,
  callback_function: (text) => {
    this.emit('partial_transcript', text);
  }
});
```

---

## 4. Migration Path

### Phase 1: Update Dependencies (Immediate)
1. Change `@xenova/transformers` to `@huggingface/transformers@^3.7.2`
2. Update import statements throughout the codebase

### Phase 2: Implement Worker Architecture (Priority)
1. Create worker file based on whisper-web pattern
2. Move pipeline creation to worker
3. Implement message passing for transcription

### Phase 3: Enhanced Features (Next)
1. Add WebGPU detection and optimization
2. Implement streaming transcription
3. Add model caching management
4. Improve audio processing with whisper-web utilities

### Phase 4: Testing and Optimization
1. Test across different devices and browsers
2. Optimize chunk sizes for performance
3. Add fallback mechanisms for edge cases

---

## 5. Conclusion

**Whisper-web demonstrates the optimal patterns** for browser-based speech recognition, while **@huggingface/transformers provides the flexibility** we need for SDK integration. By combining the architectural wisdom from whisper-web with direct transformers.js usage, we can create a robust, performant STT solution that:

1. Works offline after initial model download
2. Utilizes WebGPU when available for 10x+ speedup
3. Doesn't block the UI with Web Worker architecture
4. Handles various audio formats and sources
5. Provides real-time streaming transcription
6. Maintains small bundle size by loading models on-demand

The recommended approach balances implementation complexity with performance and user experience, making it ideal for the RunAnywhere SDK's requirements.

---

## 6. Implementation Status Update (2025-08-25)

### Fixes Applied Based on Whisper-Web Analysis

After detailed comparison with whisper-web's working implementation, the following critical fixes were applied:

#### 1. ✅ Dynamic Pipeline Configuration (FIXED)
**Problem**: Static dtype and device configuration was causing ONNX runtime errors.
**Solution**: Implemented dynamic dtype/device configuration matching whisper-web pattern.

```typescript
// Before (static configuration)
dtype: 'q8',
device: 'wasm',

// After (dynamic configuration)
dtype: data.dtype || 'q8',  // Accepts dtype from load message
device: data.device || 'wasm',  // Can switch between wasm/webgpu
```

#### 2. ✅ Simplified dtype Format (FIXED)
**Problem**: Complex dtype object structure was incompatible with ONNX models.
**Solution**: Use simple string dtype like whisper-web.

```typescript
// Before (complex object)
dtype: { encoder_model: 'fp32', decoder_model_merged: 'q4' }

// After (simple string)
dtype: 'q8'
```

#### 3. ✅ Critical Transcription Parameters (ALREADY FIXED)
The following parameters are essential for ONNX inference:
- `top_k: 0` - Forces greedy decoding
- `do_sample: false` - Disables sampling
- `force_full_sequences: false` - Prevents ONNX sequence errors

#### 4. ✅ Pipeline Factory Pattern (FIXED)
Implemented proper pipeline invalidation when configuration changes:
```typescript
if (PipelineFactory.model !== data.model_id ||
    PipelineFactory.dtype !== dtype ||
    PipelineFactory.device !== device) {
    await PipelineFactory.invalidate();
    // Update configuration
}
```

### Current Status
All critical issues identified from the "invalid data location: undefined for input 'a'" error have been addressed. The implementation now follows whisper-web's proven patterns while maintaining SDK flexibility.
