# STT Debugging Analysis - ONNX Error Investigation

## Error Description
**Error**: `invalid data location: undefined for input "a"`
**Location**: ONNX runtime during audio transcription
**Frequency**: Consistent - happens every time transcription is attempted

## Error Stack Trace
```
Error: invalid data location: undefined for input "a"
    at pc (stt-worker.js:10014:15)
    at stt-worker.js:10061:31
    at Array.map (<anonymous>)
    at dn.run (stt-worker.js:10061:17)
    at e.run (stt-worker.js:1090:34)
    at stt-worker.js:30443:82
    at async stt-worker.js:30443:29
    at async matmul (stt-worker.js:40328:16)
    at async spectrogram (stt-worker.js:36313:24)
    at async closure._extract_fbank_features (stt-worker.js:30170:28)
```

## Implementation Attempts

### 1. Initial Implementation
**Status**: ❌ Failed
**Configuration**:
```typescript
// Fixed dtype and device
dtype: 'q8',
device: 'wasm',
```
**Issue**: Static configuration, not matching whisper-web pattern

### 2. Dynamic Configuration (Like whisper-web)
**Status**: ❌ Failed
**Changes Made**:
```typescript
// Dynamic dtype and device
const device = data.device || 'wasm';
const dtype = data.dtype || (device === 'webgpu' ? 'fp32' : 'q8');

PipelineFactory.dtype = dtype;
PipelineFactory.device = device;
```
**Issue**: Still getting ONNX error

### 3. Pipeline Promise Handling
**Status**: ❌ Failed
**Changes Made**:
```typescript
// Before - awaiting pipeline creation
this.instance = await pipeline(this.task, this.model!, {...});

// After - storing promise, awaiting on return
this.instance = pipeline(this.task, this.model!, {...});
return await this.instance;
```
**Issue**: Error persists despite matching whisper-web pattern

### 4. Transcription Parameters (From whisper-web)
**Status**: ✅ Implemented
**Parameters Added**:
```typescript
const output = await pipelineInstance(audio, {
    top_k: 0,              // Forces greedy decoding
    do_sample: false,      // Disables sampling
    chunk_length_s: 30,
    stride_length_s: 5,
    language: data.language || null,
    task: data.task || 'transcribe',
    return_timestamps: true,
    force_full_sequences: false  // Prevents ONNX errors
});
```
**Issue**: Parameters are correct but error still occurs

### 5. Audio Data Handling
**Status**: ✅ Verified Correct
**Implementation**:
```typescript
// Audio is properly converted to Float32Array
if (!(audio instanceof Float32Array)) {
    if (Array.isArray(audio)) {
        audio = new Float32Array(audio);
    }
}
```
**Verification**: Audio data type and format are correct

## Comparison with Working Examples

### whisper-web (Working)
```javascript
// Pipeline creation
class PipelineFactory {
    static instance = null;

    static async getInstance(progress_callback = null) {
        if (this.instance === null) {
            this.instance = pipeline(this.task, this.model, {
                dtype: this.dtype,
                device: this.gpu ? "webgpu" : "wasm",
                progress_callback,
            });
        }
        return this.instance;
    }
}

// Usage
const transcriber = await p.getInstance((data) => {
    self.postMessage(data);
});

const output = await transcriber(audio, {
    top_k: 0,
    do_sample: false,
    // ... other params
});
```

### transformers.js examples
1. **webgpu-whisper**: Uses lower-level API (`WhisperForConditionalGeneration.from_pretrained`)
2. **whisper-word-timestamps**: Uses `@xenova/transformers` (old package)

## Key Differences Identified

### 1. Package Version
- **whisper-web**: `@huggingface/transformers@3.7.0`
- **Our implementation**: `@huggingface/transformers@3.7.2`
- Could there be a regression or breaking change?

### 2. Model Loading
- **whisper-web**: Model ID like `onnx-community/whisper-tiny`
- **Our implementation**: Same model ID
- Model loading appears successful (reaches 100%)

### 3. Pipeline Instance Storage
- **whisper-web**: Stores promise directly, no await in factory
- **Our implementation**: Now matches this pattern but still fails

### 4. Worker Context
- Both run in Web Worker context
- Both use similar message passing

## Potential Root Causes

### 1. ONNX Model Format Issue
The error occurs in the ONNX runtime when processing the spectrogram:
- Error happens during `_extract_fbank_features`
- Suggests the model's input tensor is not properly initialized
- The "input 'a'" likely refers to an internal ONNX tensor name

### 2. dtype Configuration Mismatch
Even though we're using 'q8' for WASM:
- The error might be related to how the dtype is interpreted
- The model might expect a different dtype structure

### 3. Model Cache/Loading Issue
- Model downloads to 100% but might not be properly initialized
- Cache might contain corrupted data

### 4. Transformers.js Version Issue
- Version 3.7.2 might have introduced a breaking change
- Need to test with 3.7.0 (whisper-web's version)

## Next Steps to Try

### 1. Test with Exact whisper-web Version
```json
"@huggingface/transformers": "3.7.0"
```

### 2. Clear Model Cache
```javascript
// Add cache clearing before model load
if (typeof caches !== 'undefined') {
    const cache = await caches.open('transformers-cache');
    await cache.delete(/* model URLs */);
}
```

### 3. Use Complex dtype Object (for WASM)
```typescript
dtype: {
    encoder_model: 'fp32',
    decoder_model_merged: 'q4'
}
```

### 4. Debug Model Instance
```typescript
// Log the actual pipeline instance
console.log('Pipeline instance:', pipelineInstance);
console.log('Pipeline config:', pipelineInstance?.config);
console.log('Pipeline model:', pipelineInstance?.model);
```

### 5. Test with Different Model
Try `whisper-base` instead of `whisper-tiny` to see if it's model-specific

### 6. Bypass Pipeline API
Use lower-level API like webgpu-whisper example:
```typescript
import { WhisperForConditionalGeneration, AutoProcessor, AutoTokenizer } from '@huggingface/transformers';
```

## Current Status

**Last Tested Configuration**:
- dtype: 'q8' (string)
- device: 'wasm'
- Pipeline promise properly handled
- All transcription parameters from whisper-web
- Audio as Float32Array

**Result**: ❌ Still getting "invalid data location: undefined for input 'a'" error

## Questions to Investigate

1. Why does the error specifically mention "input 'a'"?
   - This seems to be an internal ONNX tensor name
   - Suggests the model graph is not properly initialized

2. Why does model loading succeed but inference fails?
   - Model downloads completely (100%)
   - But runtime fails when processing audio

3. Is there a difference in how the audio is preprocessed?
   - Both use Float32Array
   - Sample rate should be 16kHz

4. Could this be a browser-specific issue?
   - Test in different browsers
   - Check if WebAssembly/ONNX runtime versions differ

## Action Items

- [ ] Test with @huggingface/transformers@3.7.0
- [ ] Clear browser cache and model cache
- [ ] Add detailed logging of pipeline instance
- [ ] Test with complex dtype object
- [ ] Try different Whisper model size
- [ ] Test bypass of pipeline API
- [ ] Check browser console for any WASM/ONNX warnings
