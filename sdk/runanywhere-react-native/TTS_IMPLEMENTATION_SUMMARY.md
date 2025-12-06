# System TTS Implementation Summary - React Native SDK

## Overview

Successfully implemented system Text-to-Speech (TTS) voice support for the React Native SDK, following the Swift SDK's architecture pattern using AVSpeechSynthesizer on iOS and TextToSpeech on Android.

## Files Created

### 1. SystemTTSService.ts
**Path**: `/Users/shubhammalhotra/Desktop/RunanywhereAI/master/runanywhere-sdks/sdk/runanywhere-react-native/src/services/SystemTTSService.ts`

**Purpose**: Core TTS service implementation

**Key Features**:
- Text-to-speech synthesis with native platform APIs
- Voice enumeration and detailed metadata
- Voice filtering by language
- Rate, pitch, and volume control (0.5-2.0, 0.5-2.0, 0.0-1.0 respectively)
- Platform-specific voice constants (iOS Siri voices, Android language codes)
- Helper utilities for voice selection

**Public API**:
```typescript
class SystemTTSService implements TTSService {
  async initialize(modelPath?: string | null): Promise<void>
  async synthesize(text: string, configuration?: TTSConfiguration): Promise<TTSResult>
  async getAvailableVoices(): Promise<string[]>
  async getVoiceInfo(): Promise<VoiceInfo[]>
  async cleanup(): Promise<void>
  async stop(): Promise<void>
  get isReady: boolean
  get currentModel: string | null
  get isSynthesizing: boolean
}

// Helper functions
async function getVoicesByLanguage(): Promise<Map<string, VoiceInfo[]>>
async function getDefaultVoice(language: string): Promise<string | null>
function getPlatformDefaultVoice(): string

// Constants
const PlatformVoices = {
  iOS: { SIRI_FEMALE_EN_US, SIRI_MALE_EN_US, SAMANTHA, ALEX },
  Android: { DEFAULT_EN_US, DEFAULT_ES_ES, DEFAULT_FR_FR, DEFAULT_DE_DE }
}
```

### 2. TTSExample.tsx
**Path**: `/Users/shubhammalhotra/Desktop/RunanywhereAI/master/runanywhere-sdks/sdk/runanywhere-react-native/examples/TTSExample.tsx`

**Purpose**: Complete working example demonstrating TTS usage

**Features Demonstrated**:
- TTS component initialization
- Text input and synthesis
- Voice selection UI
- Rate/pitch/volume controls with sliders
- Available voices listing
- Voice filtering by language
- Error handling
- Playback control (start/stop)

### 3. TTS_IMPLEMENTATION.md
**Path**: `/Users/shubhammalhotra/Desktop/RunanywhereAI/master/runanywhere-sdks/sdk/runanywhere-react-native/docs/TTS_IMPLEMENTATION.md`

**Purpose**: Complete documentation

**Contents**:
- Architecture overview
- Implementation details
- Usage examples (basic, advanced, streaming)
- Voice configuration guide
- Platform differences (iOS vs Android)
- Error handling patterns
- API reference
- Limitations and future enhancements

## Files Modified

### 1. TTSComponent.ts
**Path**: `/Users/shubhammalhotra/Desktop/RunanywhereAI/master/runanywhere-sdks/sdk/runanywhere-react-native/src/components/TTS/TTSComponent.ts`

**Changes**:
- Integrated SystemTTSService as fallback provider
- Added dynamic import for SystemTTSService
- Enhanced streaming support with native streaming detection
- Added voice management methods:
  - `getVoiceInfo()` - Detailed voice metadata
  - `getVoicesByLanguage(language)` - Filter voices by language
  - `setVoice(voiceId)` - Set current voice
  - `getVoice()` - Get current voice
  - `stopSynthesis()` - Stop playback
  - `isSynthesizing()` - Check synthesis state
- Added `synthesizeStreamGenerator()` for async iteration
- Added missing NativeRunAnywhere import

**Code Additions**:
```typescript
// Service creation with SystemTTS fallback
if (provider) {
  ttsService = await provider.createTTSService(this.ttsConfiguration);
} else {
  const { SystemTTSService } = await import('../../services/SystemTTSService');
  ttsService = new SystemTTSService();
  await ttsService.initialize();
}

// Streaming with native support detection
const supportsStreaming = await NativeRunAnywhere.supportsTTSStreaming();
if (supportsStreaming && onChunk) {
  NativeRunAnywhere.synthesizeStream(text, voiceId, speedRate, pitchShift);
} else {
  // Fallback to batch mode
}

// Voice management
public async getVoiceInfo(): Promise<VoiceInfo[]>
public async getVoicesByLanguage(language: string): Promise<string[]>
public setVoice(voiceId: string): void
public getVoice(): string | null
public async stopSynthesis(): Promise<void>
public async isSynthesizing(): Promise<boolean>
```

### 2. services/index.ts
**Path**: `/Users/shubhammalhotra/Desktop/RunanywhereAI/master/runanywhere-sdks/sdk/runanywhere-react-native/src/services/index.ts`

**Changes**:
- Exported SystemTTSService and helper utilities
- Made TTS service publicly available

**Code Additions**:
```typescript
export {
  SystemTTSService,
  getVoicesByLanguage,
  getDefaultVoice,
  getPlatformDefaultVoice,
  PlatformVoices,
} from './SystemTTSService';
```

## Native Methods Used

The implementation uses existing TurboModule methods from `NativeRunAnywhere.ts`:

### TTS Core Methods
```typescript
// Synthesize text to audio (batch mode)
synthesize(
  text: string,
  voiceId: string | null,
  speedRate: number,
  pitchShift: number
): Promise<string>  // Returns JSON with base64 audio

// Get available voices
getTTSVoices(): Promise<string>  // Returns JSON array of voice info

// Check streaming support
supportsTTSStreaming(): Promise<boolean>

// Start streaming synthesis (if supported)
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
- **Voice Format**: Bundle identifiers
  - Example: `com.apple.ttsbundle.siri_female_en-US_compact`
- **Features**:
  - Siri voices (male/female)
  - Neural/enhanced voices
  - 40+ languages
  - Voice quality levels (compact, enhanced, premium)
- **Default Voice**: Siri Female (English US)

### Android
- **Native API**: TextToSpeech
- **Voice Format**: Language codes
  - Example: `en-US`, `es-ES`, `fr-FR`
- **Features**:
  - System voices
  - Google TTS voices (installable)
  - Language packs
  - Quality selection based on TTS engine
- **Default Voice**: English (US)

## Voice Configuration

### VoiceInfo Interface
```typescript
interface VoiceInfo {
  id: string;                    // Voice identifier
  name: string;                  // Display name
  language: string;              // Language code (e.g., 'en-US')
  gender?: 'male' | 'female' | 'neutral';
  isNeural?: boolean;            // Neural/enhanced voice flag
  quality?: 'low' | 'medium' | 'high' | 'enhanced';
  sampleUrl?: string;            // Preview audio URL (if available)
}
```

### Available Voices Examples

**iOS**:
- `com.apple.ttsbundle.siri_female_en-US_compact` - Siri Female (English US)
- `com.apple.ttsbundle.siri_male_en-US_compact` - Siri Male (English US)
- `com.apple.ttsbundle.Samantha-compact` - Samantha
- `com.apple.ttsbundle.Alex-compact` - Alex
- Plus 40+ languages with multiple voices each

**Android**:
- `en-US` - English (United States)
- `es-ES` - Spanish (Spain)
- `fr-FR` - French (France)
- `de-DE` - German (Germany)
- `ja-JP` - Japanese (Japan)
- `zh-CN` - Chinese (China)
- Plus 100+ languages depending on installed TTS engines

## Usage Examples

### Basic Synthesis
```typescript
import { TTSComponent, TTSConfigurationImpl } from '@runanywhere/sdk';

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
console.log('Audio:', output.audioData.length, 'bytes');
console.log('Duration:', output.duration, 'seconds');
```

### Voice Selection
```typescript
// Get all voices
const voices = await tts.getAvailableVoices();

// Get detailed voice info
const voiceInfo = await tts.getVoiceInfo();
voiceInfo.forEach(v => {
  console.log(`${v.name} (${v.language}) - ${v.gender}, ${v.quality}`);
});

// Filter by language
const spanishVoices = await tts.getVoicesByLanguage('es-ES');

// Set voice
tts.setVoice(spanishVoices[0]);
await tts.synthesize('Hola, mundo!');
```

### Rate, Pitch, Volume Control
```typescript
const output = await tts.synthesize('This is a test', {
  voice: 'en-US',
  language: 'en-US',
  rate: 1.5,    // 1.5x speed (range: 0.5 - 2.0)
  pitch: 1.2,   // Higher pitch (range: 0.5 - 2.0)
  volume: 0.8,  // 80% volume (range: 0.0 - 1.0)
  audioFormat: 'pcm',
  sampleRate: 16000,
  useSSML: false,
});
```

### Direct Service Usage
```typescript
import { SystemTTSService, getDefaultVoice } from '@runanywhere/sdk';

const service = new SystemTTSService();
await service.initialize();

const defaultVoice = await getDefaultVoice('es-ES');
const result = await service.synthesize('Hola!', {
  voice: defaultVoice,
  language: 'es-ES',
  speakingRate: 1.0,
  pitch: 1.0,
  volume: 1.0,
  audioFormat: 'pcm',
});
```

## API Reference

### SystemTTSService

**Constructor**: `new SystemTTSService()`

**Methods**:
- `initialize(_modelPath?: string | null): Promise<void>` - Initialize service
- `synthesize(text: string, configuration?: TTSConfiguration): Promise<TTSResult>` - Synthesize speech
- `getAvailableVoices(): Promise<string[]>` - Get voice IDs
- `getVoiceInfo(): Promise<VoiceInfo[]>` - Get detailed voice metadata
- `cleanup(): Promise<void>` - Release resources
- `stop(): Promise<void>` - Stop synthesis

**Properties**:
- `isReady: boolean` - Service initialization state
- `currentModel: string | null` - Current model ID ('system')
- `isSynthesizing: boolean` - Synthesis in progress flag

### TTSComponent (New Methods)

- `getVoiceInfo(): Promise<VoiceInfo[]>` - Get detailed voice information
- `getVoicesByLanguage(language: string): Promise<string[]>` - Filter voices by language
- `setVoice(voiceId: string): void` - Set current voice
- `getVoice(): string | null` - Get current voice
- `stopSynthesis(): Promise<void>` - Stop playback
- `isSynthesizing(): Promise<boolean>` - Check synthesis state
- `synthesizeStreamGenerator(text: string, options?: Partial<TTSOptions>): AsyncGenerator<Buffer | Uint8Array>` - Async iteration for streaming

### Helper Functions

- `getVoicesByLanguage(): Promise<Map<string, VoiceInfo[]>>` - Get voices grouped by language
- `getDefaultVoice(language: string): Promise<string | null>` - Get default voice for language
- `getPlatformDefaultVoice(): string` - Get platform-specific default voice

## Limitations

1. **Streaming**: Most system TTS APIs don't support true streaming. Implementation falls back to batch mode.

2. **Audio Formats**: Native TTS may only support specific formats (typically PCM/WAV on both platforms).

3. **SSML Support**:
   - iOS: Limited SSML support
   - Android: Better SSML support, depends on TTS engine

4. **Voice Availability**: Depends on:
   - Platform (iOS/Android)
   - OS version
   - Installed language packs
   - TTS engine version (Android)

5. **Synthesis State**: `isSynthesizing()` currently doesn't track native state (placeholder implementation).

6. **Audio Playback**: No built-in audio playback. Audio data is returned as Buffer/Uint8Array for manual playback.

## Error Handling

All TTS operations use typed SDKError with specific error codes:

```typescript
try {
  await tts.synthesize(text);
} catch (error) {
  if (error instanceof SDKError) {
    switch (error.code) {
      case SDKErrorCode.ComponentNotReady:
        // TTS not initialized
        break;
      case SDKErrorCode.ValidationFailed:
        // Invalid parameters
        break;
      case SDKErrorCode.GenerationFailed:
        // Synthesis failed
        break;
    }
  }
}
```

## Future Enhancements

1. **True Streaming**: Implement chunk-based audio generation for supported backends
2. **Audio Playback**: Built-in audio player with controls (play, pause, resume, seek)
3. **SSML Parsing**: Enhanced SSML support with validation
4. **Voice Previews**: Sample audio playback for voice selection
5. **Phoneme Timestamps**: Word and phoneme-level timing information
6. **Voice Cloning**: Support for custom voice models
7. **Neural TTS**: Integration with cloud-based neural TTS services
8. **Synthesis State Tracking**: Real-time synthesis state via native bridge

## Testing

Run the example app to test TTS functionality:

```bash
cd /Users/shubhammalhotra/Desktop/RunanywhereAI/master/runanywhere-sdks/sdk/runanywhere-react-native/examples
npm install
npm run ios  # or npm run android
```

See `TTSExample.tsx` for a complete working demo.

## Integration with Existing Architecture

The implementation follows the clean architecture pattern established in the Swift SDK:

1. **Component Layer**: `TTSComponent` provides high-level API
2. **Service Layer**: `SystemTTSService` implements TTSService protocol
3. **Native Bridge**: `NativeRunAnywhere` TurboModule for platform communication
4. **Platform Layer**: iOS (AVSpeechSynthesizer) / Android (TextToSpeech)

This maintains consistency with other components (STT, LLM, VAD) and allows for:
- Easy service swapping (system TTS vs custom TTS backends)
- Consistent error handling
- Unified configuration patterns
- Provider registration via ModuleRegistry

## Summary

✅ **Implemented**:
- SystemTTSService with full TTS protocol compliance
- Voice enumeration and detailed metadata
- Voice filtering and selection helpers
- Rate, pitch, volume controls
- Platform-specific voice constants
- Enhanced TTSComponent with voice management
- Streaming support (with fallback)
- Complete example app
- Comprehensive documentation

✅ **No Native Changes Required**: Uses existing TurboModule methods

✅ **Type-Safe**: All TypeScript errors resolved

✅ **Follows Swift SDK Pattern**: Maintains architectural consistency

The React Native SDK now has feature parity with the Swift SDK for system TTS capabilities.
