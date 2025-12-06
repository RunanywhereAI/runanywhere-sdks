# Streaming STT Usage Example

This document demonstrates how to use the new streaming STT functionality with structured results.

## Overview

The React Native SDK now supports streaming Speech-to-Text transcription following the Swift SDK pattern. The new `streamTranscribeWithResults` method provides:

- **Partial results** as audio is processed (`isFinal: false`)
- **Final result** when transcription completes (`isFinal: true`)
- **Confidence scores** for each result
- **Timestamps** for tracking when results arrive
- **Proper error handling** without breaking the stream

## API

### New Type: STTStreamResult

```typescript
interface STTStreamResult {
  /** Transcribed text (partial or final) */
  readonly text: string;
  /** Whether this is the final result */
  readonly isFinal: boolean;
  /** Confidence score (0.0 to 1.0) */
  readonly confidence?: number;
  /** Timestamp when this result was generated */
  readonly timestamp: Date;
}
```

### New Method: streamTranscribeWithResults

```typescript
async *streamTranscribeWithResults(
  audioStream: AsyncIterable<Buffer | Uint8Array>,
  options?: Partial<STTInput['options']>
): AsyncGenerator<STTStreamResult, STTOutput, unknown>
```

## Usage Examples

### Basic Streaming Transcription

```typescript
import { STTComponent, STTConfiguration } from 'runanywhere-react-native';

// Initialize STT component
const sttConfig = new STTConfiguration({
  modelId: 'whisper-base',
  language: 'en-US',
  enablePunctuation: true,
});

const sttComponent = new STTComponent(sttConfig);
await sttComponent.initialize();

// Create audio stream (example with chunks)
async function* createAudioStream() {
  // Your audio source - could be microphone, file, etc.
  for (const chunk of audioChunks) {
    yield chunk; // Buffer or Uint8Array
  }
}

// Process streaming transcription
try {
  for await (const result of sttComponent.streamTranscribeWithResults(createAudioStream())) {
    if (result.isFinal) {
      console.log('✅ Final transcription:', result.text);
      console.log('   Confidence:', result.confidence);
    } else {
      console.log('⏳ Partial transcription:', result.text);
      console.log('   Confidence:', result.confidence);
    }
  }
} catch (error) {
  console.error('Transcription error:', error);
}
```

### Real-time UI Updates

```typescript
import React, { useState, useEffect } from 'react';

function TranscriptionComponent() {
  const [partialText, setPartialText] = useState('');
  const [finalText, setFinalText] = useState('');
  const [confidence, setConfidence] = useState<number | null>(null);
  const [isTranscribing, setIsTranscribing] = useState(false);

  const startTranscription = async (audioStream: AsyncIterable<Buffer>) => {
    setIsTranscribing(true);
    setPartialText('');
    setFinalText('');

    try {
      for await (const result of sttComponent.streamTranscribeWithResults(audioStream)) {
        if (result.isFinal) {
          setFinalText(result.text);
          setConfidence(result.confidence ?? null);
          setPartialText(''); // Clear partial text
        } else {
          setPartialText(result.text);
          setConfidence(result.confidence ?? null);
        }
      }
    } catch (error) {
      console.error('Transcription failed:', error);
    } finally {
      setIsTranscribing(false);
    }
  };

  return (
    <View>
      <Text style={styles.label}>Status:</Text>
      <Text>{isTranscribing ? 'Transcribing...' : 'Ready'}</Text>

      {partialText && (
        <>
          <Text style={styles.label}>Partial (live):</Text>
          <Text style={styles.partial}>{partialText}</Text>
        </>
      )}

      {finalText && (
        <>
          <Text style={styles.label}>Final:</Text>
          <Text style={styles.final}>{finalText}</Text>
          {confidence && (
            <Text style={styles.confidence}>
              Confidence: {(confidence * 100).toFixed(1)}%
            </Text>
          )}
        </>
      )}
    </View>
  );
}
```

### Advanced: With Custom Options

```typescript
// Configure transcription options
const options = {
  language: 'es', // Spanish
  enablePunctuation: true,
  enableTimestamps: true,
  sampleRate: 16000,
};

// Stream with options
for await (const result of sttComponent.streamTranscribeWithResults(audioStream, options)) {
  console.log(`[${result.timestamp.toISOString()}] ${result.text}`);

  if (result.isFinal) {
    // Process final result
    await saveTranscription(result.text);
  }
}
```

### Error Handling

```typescript
async function transcribeWithRetry(audioStream: AsyncIterable<Buffer>, maxRetries = 3) {
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      const results: string[] = [];

      for await (const result of sttComponent.streamTranscribeWithResults(audioStream)) {
        if (result.isFinal) {
          results.push(result.text);
        }
      }

      return results.join(' ');
    } catch (error) {
      console.error(`Attempt ${attempt} failed:`, error);

      if (attempt === maxRetries) {
        throw error;
      }

      // Wait before retry
      await new Promise(resolve => setTimeout(resolve, 1000 * attempt));
    }
  }
}
```

### Collecting All Results

```typescript
async function getAllResults(audioStream: AsyncIterable<Buffer>) {
  const partialResults: STTStreamResult[] = [];
  let finalResult: STTOutput | null = null;

  try {
    for await (const result of sttComponent.streamTranscribeWithResults(audioStream)) {
      if (result.isFinal) {
        // The return value is the final STTOutput
        console.log('Final result:', result.text);
      } else {
        // Collect partial results
        partialResults.push(result);
      }
    }

    return {
      partialResults,
      finalText: partialResults[partialResults.length - 1]?.text || '',
    };
  } catch (error) {
    console.error('Transcription error:', error);
    throw error;
  }
}
```

## Migration from Legacy API

### Old API (streamTranscribe - returns strings only)

```typescript
// Deprecated: Returns only strings
for await (const text of sttComponent.streamTranscribe(audioStream)) {
  console.log(text); // Just a string
}
```

### New API (streamTranscribeWithResults - returns structured results)

```typescript
// Recommended: Returns structured results with metadata
for await (const result of sttComponent.streamTranscribeWithResults(audioStream)) {
  console.log({
    text: result.text,
    isFinal: result.isFinal,
    confidence: result.confidence,
    timestamp: result.timestamp,
  });
}
```

## Fallback Behavior

The streaming API automatically handles services that don't support true streaming:

1. **If service supports streaming**: You get real-time partial results
2. **If service doesn't support streaming**: Audio is collected and transcribed in batch mode
   - Only one result is yielded (with `isFinal: true`)
   - Processing happens after all audio is collected

This ensures your code works consistently regardless of the underlying STT service implementation.

## Notes

- The method yields `STTStreamResult` objects during iteration
- The final return value (when using the generator's return) is a complete `STTOutput` with metadata
- Partial results may not always be available depending on the STT service capabilities
- Timestamps are captured when results are generated (not when audio was captured)
- Confidence scores may be estimated for partial results

## See Also

- [STTComponent.ts](./src/components/STT/STTComponent.ts) - Implementation
- [STTModels.ts](./src/components/STT/STTModels.ts) - Type definitions
- Swift SDK Reference: `sdk/runanywhere-swift/Sources/RunAnywhere/Components/STT/STTComponent.swift`
