# Transformers.js Bundle Size Solution Guide

## Problem Statement
When importing @huggingface/transformers (v3.x) directly in a Next.js or React application, it causes "Maximum call stack size exceeded" errors due to the library's massive bundle size (100MB+). This makes the application unloadable.

## Root Cause Analysis
1. **Direct Import Issue**: Any direct import of transformers.js in the main bundle causes webpack/vite to include the entire library
2. **Circular Dependencies**: The library has complex internal dependencies that can cause stack overflow during bundling
3. **Next.js SSR**: Server-side rendering tries to bundle everything, exacerbating the issue
4. **SDK Package Imports**: Importing SDK packages that internally use transformers.js brings the same problem

## The Solution: Complete Worker Isolation Pattern

### Core Principle
**NEVER import transformers.js in your main application bundle. ONLY import it in Web Workers.**

### Implementation Architecture

```
┌─────────────────┐
│   Main Thread   │
│   (React App)   │
│   ~5MB bundle   │
└────────┬────────┘
         │ postMessage
         ↓
┌─────────────────┐
│   Web Worker    │
│ (transformers)  │
│  ~100MB bundle  │
└─────────────────┘
```

## Step-by-Step Implementation

### 1. Create a Dedicated Worker File
Create `public/worker.js` or `src/worker.js`:

```javascript
// worker.js - ONLY place where transformers.js is imported
import { pipeline, env } from '@huggingface/transformers';

// Configure environment
env.allowLocalModels = false;
env.backends.onnx.wasm.proxy = false;

// Singleton pattern for model management
class PipelineFactory {
    static task = 'automatic-speech-recognition';
    static model = 'Xenova/whisper-tiny';
    static instance = null;

    static async getInstance(progress_callback = null) {
        if (this.instance === null) {
            this.instance = await pipeline(this.task, this.model, {
                dtype: { encoder_model: 'fp32', decoder_model_merged: 'q4' },
                device: 'wasm',
                progress_callback,
            });
        }
        return this.instance;
    }
}

// Message handler
self.addEventListener('message', async (event) => {
    const { type, audio, model } = event.data;

    try {
        switch (type) {
            case 'load':
                await PipelineFactory.getInstance((progress) => {
                    self.postMessage({
                        status: 'progress',
                        progress: progress.progress
                    });
                });
                self.postMessage({ status: 'ready' });
                break;

            case 'transcribe':
                const transcriber = await PipelineFactory.getInstance();
                const result = await transcriber(audio);
                self.postMessage({
                    status: 'complete',
                    data: result
                });
                break;
        }
    } catch (error) {
        self.postMessage({
            status: 'error',
            data: { message: error.message }
        });
    }
});
```

### 2. Create a Hook for Worker Communication
```typescript
// hooks/useTransformersWorker.ts
import { useState, useRef, useCallback, useEffect } from 'react';

export function useTransformersWorker() {
    const [isLoading, setIsLoading] = useState(false);
    const [progress, setProgress] = useState(0);
    const workerRef = useRef<Worker | null>(null);

    useEffect(() => {
        // Create worker with proper module support
        const worker = new Worker(
            new URL('/worker.js', import.meta.url),
            { type: 'module' }
        );

        worker.addEventListener('message', (event) => {
            const { status, progress, data } = event.data;

            switch (status) {
                case 'progress':
                    setProgress(progress);
                    break;
                case 'ready':
                    setIsLoading(false);
                    break;
                case 'error':
                    console.error('Worker error:', data);
                    setIsLoading(false);
                    break;
            }
        });

        workerRef.current = worker;

        // Load model
        worker.postMessage({ type: 'load' });
        setIsLoading(true);

        return () => {
            worker.terminate();
        };
    }, []);

    const transcribe = useCallback(async (audio: Float32Array) => {
        if (!workerRef.current) return null;

        return new Promise((resolve) => {
            const handler = (event: MessageEvent) => {
                if (event.data.status === 'complete') {
                    workerRef.current?.removeEventListener('message', handler);
                    resolve(event.data.data);
                }
            };

            workerRef.current.addEventListener('message', handler);
            workerRef.current.postMessage({
                type: 'transcribe',
                audio
            });
        });
    }, []);

    return { isLoading, progress, transcribe };
}
```

### 3. Next.js Configuration
```typescript
// next.config.ts
const nextConfig: NextConfig = {
    webpack: (config, { isServer }) => {
        if (!isServer) {
            // Client-side only configurations
            config.resolve.alias = {
                ...config.resolve.alias,
                'onnxruntime-node': 'onnxruntime-web',
            };

            config.resolve.fallback = {
                fs: false,
                path: false,
                crypto: false,
            };
        }

        // DON'T use IgnorePlugin for transformers
        // Let the worker handle it separately

        return config;
    },
};
```

### 4. For SDK Packages
If you have SDK packages that use transformers.js:

**DON'T DO THIS:**
```typescript
// ❌ Bad: SDK imports transformers directly
// packages/stt-whisper/src/index.ts
import { pipeline } from '@huggingface/transformers';

export class WhisperAdapter {
    async transcribe() {
        const model = await pipeline(...); // Bundle explosion!
    }
}
```

**DO THIS INSTEAD:**
```typescript
// ✅ Good: SDK communicates with worker
// packages/stt-whisper/src/index.ts
export class WhisperAdapter {
    private worker: Worker | null = null;

    async initialize() {
        // Create worker that imports transformers
        this.worker = new Worker('/whisper-worker.js', { type: 'module' });
    }

    async transcribe(audio: Float32Array) {
        // Communicate via postMessage
        this.worker?.postMessage({ type: 'transcribe', audio });
    }
}
```

## Key Configuration Points

### 1. TypeScript Configuration
```json
{
  "compilerOptions": {
    "target": "ES2020",      // Modern target for worker support
    "module": "ESNext",      // ES modules
    "moduleResolution": "bundler", // For vite/webpack
    "lib": ["dom", "dom.iterable", "esnext", "webworker"]
  }
}
```

### 2. Package.json Dependencies
```json
{
  "dependencies": {
    "@huggingface/transformers": "3.7.2" // Pin specific version
  }
}
```

### 3. Worker File Location
- **For Vite**: Place in `src/worker.js`
- **For Next.js**: Place in `public/worker.js` and copy to output

## Common Pitfalls to Avoid

### ❌ DON'T: Import in React Components
```typescript
// This will crash your app
import { pipeline } from '@huggingface/transformers';

export function MyComponent() {
    // ...
}
```

### ❌ DON'T: Dynamic Import in Main Thread
```typescript
// This still loads in main bundle
const transformers = await import('@huggingface/transformers');
```

### ❌ DON'T: Use in Server-Side Code
```typescript
// pages/api/transcribe.ts
import { pipeline } from '@huggingface/transformers'; // SSR crash
```

### ✅ DO: Complete Isolation
```typescript
// Only in worker.js
import { pipeline } from '@huggingface/transformers';

// Everything else uses postMessage
```

## Testing the Solution

1. **Bundle Size Check**: Main bundle should be <10MB
2. **Worker Loading**: Check Network tab for separate worker bundle
3. **Memory Usage**: Monitor DevTools Memory tab
4. **Performance**: Main thread should remain responsive

## Debugging Tips

1. **Check Imports**: Search entire codebase for transformers imports
   ```bash
   grep -r "from '@huggingface/transformers'" --include="*.ts" --include="*.tsx" --include="*.js"
   ```

2. **Bundle Analysis**: Use webpack-bundle-analyzer or vite-bundle-visualizer

3. **Worker Errors**: Check browser console for worker-specific errors

4. **Network Tab**: Verify worker.js loads separately from main bundle

## Summary

The key to using transformers.js in web applications is **complete isolation in Web Workers**. This pattern:
- Keeps main bundle small and fast
- Loads ML models on-demand
- Maintains UI responsiveness
- Avoids SSR issues
- Prevents bundle size explosions

Remember: **The main thread should NEVER know transformers.js exists. Only workers should import it.**
