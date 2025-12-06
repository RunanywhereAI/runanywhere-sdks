# System TTS Implementation - React Native SDK

## Overview

The React Native SDK now includes a complete System TTS (Text-to-Speech) implementation that mirrors the Swift SDK's architecture. This implementation provides native TTS synthesis capabilities on both iOS and Android platforms.

## Architecture

The TTS implementation follows the clean architecture pattern established in the Swift SDK:

```
TTSComponent (High-level API)
    ↓
SystemTTSService (Service Implementation)
    ↓
NativeRunAnywhere TurboModule (Native Bridge)
    ↓
Platform Native TTS (AVSpeechSynthesizer/TextToSpeech)
```

## Files Created/Modified

### 1. SystemTTSService.ts
**Location**: `/src/services/SystemTTSService.ts`

**Purpose**: Implementation of the TTSService protocol using native platform TTS APIs

**Key Features**:
- Text-to-speech synthesis with configurable voice, rate, pitch, and volume
- Voice enumeration and filtering by language
- Voice metadata (name, language, gender, quality)
- Platform-specific voice constants
- Helper utilities for voice selection

**Methods**:
```typescript
class SystemTTSService implements TTSService {
  async initialize(modelPath?: string | null): Promise<void>
  async synthesize(text: string, configuration?: TTSConfiguration): Promise<TTSResult>
  async getAvailableVoices(): Promise<string[]>
  async getVoiceInfo(): Promise<VoiceInfo[]>
  async cleanup(): Promise<void>
  async stop(): Promise<void>
}
```

**Helper Functions**:
```typescript
// Get voices grouped by language
async getVoicesByLanguage(): Promise<Map<string, VoiceInfo[]>>

// Get default voice for a language
async getDefaultVoice(language: string): Promise<string | null>

// Get platform-specific default voice
getPlatformDefaultVoice(): string
```

### 2. TTSComponent.ts (Updated)
**Location**: `/src/components/TTS/TTSComponent.ts`

**Updates**:
- Integrated SystemTTSService as fallback when no TTS provider is registered
- Added streaming synthesis support (with fallback to batch mode)
- Added voice management methods:
  - `getVoiceInfo()` - Get detailed voice metadata
  - `getVoicesByLanguage(language)` - Filter voices by language
  - `setVoice(voiceId)` - Set current voice
  - `getVoice()` - Get current voice
  - `stopSynthesis()` - Stop playback
  - `isSynthesizing()` - Check synthesis state
- Added `synthesizeStreamGenerator()` for modern async iteration

### 3. Services Index (Updated)
**Location**: `/src/services/index.ts`

**Updates**:
- Exported SystemTTSService and helper utilities
- Made TTS service available for direct use

## Native Module Methods Used

The implementation uses the following TurboModule methods from `NativeRunAnywhere.ts`:

### TTS Methods
```typescript
// Synthesize text to audio
synthesize(
  text: string,
  voiceId: string | null,
  speedRate: number,
  pitchShift: number
): Promise<string>

// Get available voices
getTTSVoices(): Promise<string>

// Check if streaming is supported
supportsTTSStreaming(): Promise<boolean>

// Start streaming synthesis
synthesizeStream(
  text: string,
  voiceId: string | null,
  speedRate: number,
  pitchShift: number
): void

// Cancel ongoing synthesis
cancelTTS(): void
```

## Platform Support

### iOS
- **Native API**: AVSpeechSynthesizer
- **Voice Format**: Bundle identifiers (e.g., `com.apple.ttsbundle.siri_female_en-US_compact`)
- **Features**:
  - Siri voices
  - Neural voices
  - Multiple languages
  - Voice quality levels

### Android
- **Native API**: TextToSpeech
- **Voice Format**: Language codes (e.g., `en-US`, `es-ES`)
- **Features**:
  - System voices
  - Google TTS voices
  - Language packs
  - Quality selection

## Usage Examples

### Basic Synthesis

```typescript
import { TTSComponent } from '@runanywhere/sdk';
import { TTSConfigurationImpl } from '@runanywhere/sdk';

// Create configuration
const config = new TTSConfigurationImpl({
  voice: 'system',
  language: 'en-US',
  speakingRate: 1.0,
  pitch: 1.0,
  volume: 1.0,
});

// Initialize component
const tts = new TTSComponent(config);
await tts.initialize();

// Synthesize speech
const output = await tts.synthesize('Hello, world!');
console.log('Audio data:', output.audioData);
console.log('Duration:', output.duration);
```

### Voice Selection

```typescript
// Get all available voices
const voices = await tts.getAvailableVoices();
console.log('Available voices:', voices);

// Get detailed voice information
const voiceInfo = await tts.getVoiceInfo();
voiceInfo.forEach(v => {
  console.log(`${v.name} (${v.language}) - ${v.quality}`);
});

// Get voices for specific language
const englishVoices = await tts.getVoicesByLanguage('en-US');

// Set voice
tts.setVoice(englishVoices[0]);
```

### Rate, Pitch, Volume Control

```typescript
// Synthesize with custom parameters
const output = await tts.synthesize('This is a test', {
  voice: 'en-US',
  language: 'en-US',
  rate: 1.5,    // 1.5x speed (0.5 - 2.0)
  pitch: 1.2,   // Higher pitch (0.5 - 2.0)
  volume: 0.8,  // 80% volume (0.0 - 1.0)
  audioFormat: 'pcm',
  sampleRate: 16000,
  useSSML: false,
});
```

### Direct Service Usage

```typescript
import { SystemTTSService, getDefaultVoice } from '@runanywhere/sdk';

// Create service directly
const service = new SystemTTSService();
await service.initialize();

// Get default voice for language
const defaultVoice = await getDefaultVoice('es-ES');

// Synthesize
const result = await service.synthesize('Hola, mundo!', {
  voice: defaultVoice,
  language: 'es-ES',
  speakingRate: 1.0,
  pitch: 1.0,
  volume: 1.0,
  audioFormat: 'pcm',
});
```

### Streaming (when supported)

```typescript
// Check if streaming is supported
const supportsStreaming = await NativeRunAnywhere.supportsTTSStreaming();

if (supportsStreaming) {
  // Use streaming synthesis
  for await (const chunk of tts.synthesizeStreamGenerator(longText)) {
    console.log('Received audio chunk:', chunk.length, 'bytes');
    // Process chunk (play, save, etc.)
  }
} else {
  // Fallback to batch synthesis
  const output = await tts.synthesize(longText);
}
```

### Stop Synthesis

```typescript
// Start synthesis
const synthesisPromise = tts.synthesize('Long text...');

// Stop after 2 seconds
setTimeout(async () => {
  await tts.stopSynthesis();
}, 2000);
```

## Voice Configuration

### Platform-Specific Voices

```typescript
import { PlatformVoices, getPlatformDefaultVoice } from '@runanywhere/sdk';

// iOS voices
const iosVoice = PlatformVoices.iOS.SIRI_FEMALE_EN_US;

// Android voices
const androidVoice = PlatformVoices.Android.DEFAULT_EN_US;

// Get platform default
const defaultVoice = getPlatformDefaultVoice();
```

### Voice Filtering

```typescript
import { getVoicesByLanguage } from '@runanywhere/sdk';

// Get all voices grouped by language
const voiceMap = await getVoicesByLanguage();

// Access voices for specific language
const spanishVoices = voiceMap.get('es-ES');
spanishVoices?.forEach(voice => {
  console.log(`${voice.name}: ${voice.quality}, ${voice.gender}`);
});
```

## Voice Metadata

The `VoiceInfo` interface provides detailed voice information:

```typescript
interface VoiceInfo {
  id: string;              // Voice identifier
  name: string;            // Display name
  language: string;        // Language code (e.g., 'en-US')
  gender?: 'male' | 'female' | 'neutral';
  isNeural?: boolean;      // Neural/enhanced voice
  quality?: 'low' | 'medium' | 'high' | 'enhanced';
  sampleUrl?: string;      // Preview audio URL
}
```

## Error Handling

```typescript
try {
  const output = await tts.synthesize(text);
} catch (error) {
  if (error instanceof SDKError) {
    switch (error.code) {
      case SDKErrorCode.ComponentNotReady:
        console.error('TTS not initialized');
        break;
      case SDKErrorCode.ValidationFailed:
        console.error('Invalid parameters:', error.message);
        break;
      case SDKErrorCode.InferenceFailed:
        console.error('Synthesis failed:', error.message);
        break;
    }
  }
}
```

## Configuration Options

### TTSConfiguration

```typescript
interface TTSConfiguration {
  componentType: SDKComponent.TTS;
  modelId: string | null;          // Not used for system TTS
  voice: string;                   // Voice ID or 'system'
  language: string;                // Language code (e.g., 'en-US')
  speakingRate: number;            // 0.5 - 2.0
  pitch: number;                   // 0.5 - 2.0
  volume: number;                  // 0.0 - 1.0
  audioFormat: string;             // 'pcm', 'mp3', 'wav'
  useNeuralVoice: boolean;         // Prefer neural voices
  enableSSML: boolean;             // Support SSML markup
}
```

### TTSOptions (per-synthesis)

```typescript
interface TTSOptions {
  voice: string | null;
  language: string;
  rate: number;
  pitch: number;
  volume: number;
  audioFormat: string;
  sampleRate: number;
  useSSML: boolean;
}
```

## Available Voices

### iOS (Example)
- `com.apple.ttsbundle.siri_female_en-US_compact` - Siri Female (English US)
- `com.apple.ttsbundle.siri_male_en-US_compact` - Siri Male (English US)
- `com.apple.ttsbundle.Samantha-compact` - Samantha
- `com.apple.ttsbundle.Alex-compact` - Alex
- Plus many more languages and voices

### Android (Example)
- `en-US` - English (United States)
- `es-ES` - Spanish (Spain)
- `fr-FR` - French (France)
- `de-DE` - German (Germany)
- `ja-JP` - Japanese (Japan)
- Plus many more via Google TTS

## Limitations

1. **Streaming**: Most system TTS APIs don't support true streaming. The implementation falls back to batch synthesis.

2. **Audio Format**: Native TTS may only support specific formats. The service handles format conversion where possible.

3. **SSML Support**: SSML support varies by platform and voice. iOS has limited SSML support; Android has better support.

4. **Voice Availability**: Available voices depend on:
   - Platform (iOS/Android)
   - OS version
   - Installed language packs
   - TTS engine version

5. **Synthesis State**: `isSynthesizing()` currently doesn't track native state. This would require additional native implementation.

## Future Enhancements

1. **True Streaming Support**: Implement chunk-based audio generation for supported backends

2. **Audio Playback**: Add built-in audio playback with controls (play, pause, resume, seek)

3. **SSML Parsing**: Enhanced SSML support with validation and preprocessing

4. **Voice Previews**: Sample audio playback for voice selection

5. **Phoneme Timestamps**: Word and phoneme-level timing information

6. **Voice Cloning**: Support for custom voice models

7. **Neural TTS**: Integration with cloud-based neural TTS services

## Testing

See `examples/TTSExample.tsx` for a complete working example with:
- Voice selection UI
- Rate/pitch/volume controls
- Text input and synthesis
- Error handling
- Voice filtering by language

## See Also

- [Swift SDK TTS Documentation](../../runanywhere-swift/Sources/RunAnywhere/Components/TTS/)
- [NativeRunAnywhere Spec](../src/NativeRunAnywhere.ts)
- [TTSComponent](../src/components/TTS/TTSComponent.ts)
- [SystemTTSService](../src/services/SystemTTSService.ts)
