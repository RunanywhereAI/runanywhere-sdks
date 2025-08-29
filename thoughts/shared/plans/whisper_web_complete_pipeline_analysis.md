# Whisper-Web Complete Audio Pipeline Analysis

## Executive Summary

**CRITICAL FINDING**: Our implementation appears to be **nearly identical** to the working fork, but the error "invalid data location: undefined for input 'a'" suggests a **subtle but critical difference** in how the audio data is being processed by the ONNX runtime.

**Root Cause**: The error occurs INSIDE the ONNX model execution, not in our JavaScript code. This indicates the Float32Array is reaching the model but in an unexpected format or state.

## 1. Working Fork's Complete Audio Pipeline

### 1.1 Audio Capture Stage
**File**: `AudioRecorder.tsx` (lines 37-85)

```typescript
// MediaRecorder with automatic mime type detection
const mimeType = getMimeType(); // Tries audio/webm, audio/mp4, audio/ogg, etc.
const mediaRecorder = new MediaRecorder(stream, { mimeType });

// Records to Blob chunks
mediaRecorder.addEventListener("dataavailable", (event) => {
    chunksRef.current.push(event.data);
    let blob = new Blob(chunksRef.current, { type: mimeType });
    // WebM duration fix applied if needed
    if (mimeType === "audio/webm") {
        blob = await webmFixDuration(blob, duration, blob.type);
    }
});
```

### 1.2 Audio Processing Stage
**File**: `AudioManager.tsx` (lines 67-90)

```typescript
const setAudioFromRecording = async (data: Blob) => {
    const audioCTX = new AudioContext({
        sampleRate: Constants.SAMPLING_RATE  // 16000 Hz
    });
    const arrayBuffer = fileReader.result as ArrayBuffer;
    const decoded = await audioCTX.decodeAudioData(arrayBuffer);
    // Stores AudioBuffer for transcription
};
```

### 1.3 Audio Conversion Stage
**File**: `useTranscriber.ts` (lines 141-155)

```typescript
const postRequest = async (audioData: AudioBuffer) => {
    let audio;
    if (audioData.numberOfChannels === 2) {
        const SCALING_FACTOR = Math.sqrt(2);
        const left = audioData.getChannelData(0);
        const right = audioData.getChannelData(1);

        audio = new Float32Array(left.length);
        for (let i = 0; i < audioData.length; ++i) {
            audio[i] = (SCALING_FACTOR * (left[i] + right[i])) / 2;
        }
    } else {
        audio = audioData.getChannelData(0);
    }

    webWorker.postMessage({ audio, model, dtype, gpu, subtask, language });
};
```

### 1.4 Worker Processing Stage
**File**: `worker.js` (lines 137-156)

```javascript
// Direct transcription call
const output = await transcriber(audio, {
    top_k: 0,
    do_sample: false,
    chunk_length_s,
    stride_length_s,
    language,
    task: subtask,
    return_timestamps: true,
    force_full_sequences: false,
    streamer,
});
```

## 2. Our Implementation Pipeline

### 2.1 Audio Capture Stage
**File**: `page.tsx` (lines 79-121)

```typescript
// Nearly identical MediaRecorder setup
const recorder = new MediaRecorder(stream, {
    mimeType: 'audio/webm;codecs=opus'  // Fixed format vs fork's auto-detection
});
```

### 2.2 Audio Processing Stage
**File**: `page.tsx` (lines 130-148)

```typescript
const processRecordedAudio = async (blob: Blob) => {
    const audioContext = createAudioContext();  // Uses 16kHz sample rate
    const arrayBuffer = await blob.arrayBuffer();
    const audioBuffer = await audioContext.decodeAudioData(arrayBuffer);

    const audio = convertStereoToMono(audioBuffer);  // Identical to fork
};
```

### 2.3 Audio Conversion Stage
**File**: `utils/audio.ts` (lines 3-17)

```typescript
// IDENTICAL to fork implementation
export function convertStereoToMono(audioData: AudioBuffer): Float32Array {
  if (audioData.numberOfChannels === 2) {
    const SCALING_FACTOR = Math.sqrt(2);
    const left = audioData.getChannelData(0);
    const right = audioData.getChannelData(1);

    const audio = new Float32Array(left.length);
    for (let i = 0; i < left.length; ++i) {
      audio[i] = (SCALING_FACTOR * (left[i] + right[i])) / 2;
    }
    return audio;
  } else {
    return audioData.getChannelData(0);
  }
}
```

### 2.4 Worker Processing Stage
**File**: `worker.ts` (lines 146-172)

```typescript
// IDENTICAL transcriber call pattern
const output = await transcriber(audio, {
    top_k: 0,
    do_sample: false,
    chunk_length_s,
    stride_length_s,
    language,
    task: subtask,
    return_timestamps: true,
    force_full_sequences: false,
    streamer,
});
```

## 3. Critical Differences Analysis

### 3.1 Versions & Dependencies
✅ **IDENTICAL**: Both use `@huggingface/transformers: 3.7.0`
✅ **IDENTICAL**: Both use same ONNX community models
✅ **IDENTICAL**: Both use WASM device mode

### 3.2 Audio Configuration
✅ **IDENTICAL**: Sample rate 16kHz
✅ **IDENTICAL**: Stereo-to-mono conversion algorithm
✅ **IDENTICAL**: SCALING_FACTOR = Math.sqrt(2)

### 3.3 Worker Implementation
✅ **IDENTICAL**: Pipeline Factory pattern
✅ **IDENTICAL**: AutomaticSpeechRecognitionPipelineFactory
✅ **IDENTICAL**: Model lifecycle management
✅ **IDENTICAL**: WhisperTextStreamer setup
✅ **IDENTICAL**: Transcriber call parameters

### 3.4 Key Differences Found

#### 3.4.1 MediaRecorder MIME Type
- **Fork**: Auto-detects best MIME type (`getMimeType()`)
- **Ours**: Fixed to `'audio/webm;codecs=opus'`

#### 3.4.2 WebM Duration Fix
- **Fork**: Applies `webmFixDuration()` for WebM files
- **Ours**: **MISSING** - No duration fix applied

#### 3.4.3 File Processing Approach
- **Fork**: Uses FileReader with progress tracking
- **Ours**: Direct arrayBuffer() call

## 4. Error Analysis: "invalid data location: undefined for input 'a'"

### 4.1 Error Location
- **Not in our JavaScript**: Debug logs show Float32Array reaching worker correctly
- **Inside ONNX Runtime**: Error occurs during model.forward() call
- **Input Tensor Creation**: The error happens when ONNX tries to create input tensor

### 4.2 Possible Root Causes

#### 4.2.1 Memory Layout Issues
The Float32Array might have the wrong memory layout:
```javascript
// Potential issue: SharedArrayBuffer vs ArrayBuffer
// Potential issue: Detached ArrayBuffer
// Potential issue: Wrong byte offset/stride
```

#### 4.2.2 Audio Buffer Corruption
```javascript
// Our MediaRecorder might produce corrupted audio due to:
// - Missing WebM duration fix
// - Fixed MIME type vs auto-detection
// - Different codec handling
```

#### 4.2.3 Transformers.js Version Inconsistency
```javascript
// Even though both use 3.7.0, there might be:
// - Different build artifacts
// - Different bundling approach
// - Missing polyfills or patches
```

## 5. Critical Missing Components

### 5.1 WebM Duration Fix
**File**: Fork's `BlobFix.ts` - **COMPLETELY MISSING** from our implementation

```typescript
// MISSING: This could be critical for proper audio decoding
if (mimeType === "audio/webm") {
    blob = await webmFixDuration(blob, duration, blob.type);
}
```

### 5.2 MIME Type Auto-Detection
**File**: Fork's `AudioRecorder.tsx` lines 7-21

```typescript
// MISSING: We use fixed MIME type instead of auto-detection
function getMimeType() {
    const types = ["audio/webm", "audio/mp4", "audio/ogg", "audio/wav", "audio/aac"];
    for (let i = 0; i < types.length; i++) {
        if (MediaRecorder.isTypeSupported(types[i])) {
            return types[i];
        }
    }
    return undefined;
}
```

### 5.3 FileReader Progress Pattern
**File**: Fork's `AudioManager.tsx` lines 71-89

```typescript
// MISSING: We use direct arrayBuffer() instead of FileReader
const fileReader = new FileReader();
fileReader.onprogress = (event) => {
    setProgress(event.loaded / event.total || 0);
};
fileReader.onloadend = async () => {
    const arrayBuffer = fileReader.result as ArrayBuffer;
    // Process audio...
};
fileReader.readAsArrayBuffer(data);
```

## 6. Action Plan

### 6.1 Immediate Fixes (High Priority)

#### Fix 1: Add WebM Duration Fix
```typescript
// Need to implement webmFixDuration from BlobFix.ts
// This is critical for proper WebM audio decoding
```

#### Fix 2: Implement MIME Type Auto-Detection
```typescript
// Replace fixed MIME type with getMimeType() function
// This ensures optimal codec selection
```

#### Fix 3: Switch to FileReader Pattern
```typescript
// Use FileReader instead of direct arrayBuffer()
// This matches fork's exact processing approach
```

### 6.2 Deep Investigation (Medium Priority)

#### Investigation 1: Audio Buffer Validation
```typescript
// Add extensive logging to compare audio buffers
// Check for memory corruption or layout issues
```

#### Investigation 2: ONNX Runtime State
```typescript
// Compare ONNX runtime initialization between implementations
// Check for missing configuration or environment differences
```

### 6.3 Last Resort (Low Priority)

#### Option 1: Direct Fork Integration
```typescript
// If fixes don't work, directly copy fork's exact worker implementation
// Use their exact file structure and build process
```

## 7. Hypothesis: The Real Issue

**Primary Hypothesis**: The WebM duration fix is **critical** for proper audio decoding. Without it:

1. WebM files have incorrect duration metadata
2. AudioContext.decodeAudioData() produces corrupted AudioBuffer
3. getChannelData() returns Float32Array with wrong memory layout
4. ONNX runtime can't process the malformed tensor

**Secondary Hypothesis**: MIME type auto-detection ensures optimal codec, and fixed codec might produce incompatible audio streams.

## 8. Next Steps

1. **IMPLEMENT** WebM duration fix from fork
2. **IMPLEMENT** MIME type auto-detection
3. **SWITCH** to FileReader pattern for audio processing
4. **TEST** each change individually to isolate the fix
5. **VALIDATE** that audio reaches ONNX in identical format to fork

The error suggests we're 99% there - it's likely a single missing piece in the audio processing pipeline that's causing the ONNX runtime to receive malformed input tensors.
