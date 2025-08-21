# FluidAudioDiarization Module

A self-contained speaker diarization module for RunAnywhereSDK using FluidAudio.

## Features

- **Speaker Diarization**: Identifies and separates different speakers in audio
- **17.7% DER**: Competitive diarization error rate using FluidAudio models
- **Real-time Processing**: 0.02x RTF (50x faster than real-time)
- **Speaker Tracking**: Maintains speaker identities throughout the session
- **Speaker Enrollment**: Allows naming speakers for personalized identification

## Requirements

- iOS 17.0+ / macOS 14.0+ (required by FluidAudio)
- Swift 5.9+
- RunAnywhereSDK

## Installation

### Option 1: Add as Local Package in Xcode (Recommended for Development)

1. Open your Xcode project
2. Select File → Add Package Dependencies
3. Click "Add Local..."
4. Navigate to `/sdk/runanywhere-swift/Modules/FluidAudioDiarization`
5. Click "Add Package"
6. Select your app target and add `FluidAudioDiarization` product

### Option 2: Add via Swift Package Manager

In your `Package.swift`:

```swift
dependencies: [
    .package(path: "../path/to/sdk/runanywhere-swift/Modules/FluidAudioDiarization"),
    // ... other dependencies
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            "FluidAudioDiarization",
            // ... other dependencies
        ]
    )
]
```

### Option 3: Add to Xcode Project via Package.swift

If your iOS app uses a Package.swift file, add:

```swift
dependencies: [
    .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.3.0"),
    .package(path: "../../sdk/runanywhere-swift"),  // RunAnywhereSDK
    .package(path: "../../sdk/runanywhere-swift/Modules/FluidAudioDiarization"),
]
```

## Usage

```swift
import FluidAudioDiarization
import RunAnywhereSDK

// Initialize the diarization service
let diarization = try await FluidAudioDiarization(threshold: 0.7)

// Detect speaker from audio buffer
let audioBuffer: [Float] = // your 16kHz audio data
let speaker = diarization.detectSpeaker(from: audioBuffer, sampleRate: 16000)
print("Speaker detected: \(speaker.id)")

// Update speaker name (for enrollment)
diarization.updateSpeakerName(speakerId: speaker.id, name: "Alice")

// Get all detected speakers
let allSpeakers = diarization.getAllSpeakers()

// Perform detailed diarization
let result = try await diarization.performDetailedDiarization(audioBuffer: audioBuffer)
for segment in result?.segments ?? [] {
    print("Speaker \(segment.speakerId): \(segment.startTime)s - \(segment.endTime)s")
}

// Compare two speakers
let similarity = try await diarization.compareSpeakers(audio1: buffer1, audio2: buffer2)
print("Speaker similarity: \(similarity)")

// Reset diarization state
diarization.reset()
```

## Integration with RunAnywhereSDK Voice Pipeline

The module integrates seamlessly with RunAnywhereSDK's voice pipeline:

```swift
// Enable speaker diarization in voice pipeline
let config = ModularPipelineConfig.transcriptionWithVAD(
    sttModel: "whisper-base",
    vadThreshold: 0.02
)

let pipeline = sdk.createVoicePipeline(config: config)
pipeline.enableSpeakerDiarization(true)  // This will use FluidAudioDiarization if available
```

## Troubleshooting

### Package Resolution Failed Error

If you see dependency resolution errors when adding the module:

1. Ensure you're using Xcode 15.0 or later
2. Clean build folder: Product → Clean Build Folder
3. Reset package caches: File → Packages → Reset Package Caches
4. If using CocoaPods in your project, ensure the workspace is properly configured

### Platform Version Errors

FluidAudio requires iOS 17.0+/macOS 14.0+. If your app targets lower versions:
- Update your app's minimum deployment target, or
- Use the default speaker diarization implementation from RunAnywhereSDK

### Build Errors

If the module fails to build:

1. Verify FluidAudio is accessible:
   ```bash
   swift package resolve
   ```

2. Check that RunAnywhereSDK is properly built:
   ```bash
   cd ../../  # Navigate to SDK root
   swift build
   ```

## Dependencies

- [FluidAudio](https://github.com/FluidInference/FluidAudio.git) v0.3.0+
- RunAnywhereSDK (local dependency)

## License

Same as RunAnywhereSDK - see main repository for details.
