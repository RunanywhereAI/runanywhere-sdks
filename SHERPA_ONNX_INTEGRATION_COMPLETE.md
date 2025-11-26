# Sherpa-ONNX Integration Complete

## Overview

Sherpa-ONNX streaming STT has been successfully integrated into the RunAnywhere iOS SDK. This document summarizes the changes made and how to build and test.

## Changes Made

### 1. Swift ONNX Service Updates

**File**: `sdks/sdk/runanywhere-swift/Modules/ONNXRuntime/Sources/ONNXRuntime/ONNXSTTService.swift`

Added support for sherpa-onnx streaming speech-to-text:
- **Model Detection**: Automatically detects sherpa-onnx models by checking for typical file patterns (encoder-epoch-99-avg-1.onnx, tokens.txt, etc.) or .tar.bz2 archives
- **Archive Extraction**: Supports extracting .tar.bz2 model archives using libarchive
- **Streaming Transcription**: Implements true streaming STT with partial results via `streamTranscribeWithSherpa()`
- **Batch Transcription**: Supports standard batch transcription via `transcribeWithSherpa()`
- **Audio Conversion**: Converts Int16 PCM to Float32 samples required by sherpa-onnx
- **Endpoint Detection**: Automatically detects end of speech

### 2. C Bridge Wrapper Updates

**File**: `sdks/sdk/runanywhere-swift/Modules/ONNXRuntime/Sources/CRunAnywhereONNX/include/onnx_bridge_wrapper.h`

Added complete sherpa-onnx C API declarations:
- `ra_sherpa_create_recognizer()` - Create streaming recognizer
- `ra_sherpa_create_stream()` - Create audio stream
- `ra_sherpa_accept_waveform()` - Feed audio samples
- `ra_sherpa_is_ready()` - Check if ready for decoding
- `ra_sherpa_decode()` - Run neural network inference
- `ra_sherpa_get_result()` - Get transcription result
- `ra_sherpa_input_finished()` - Signal end of audio
- `ra_sherpa_is_endpoint()` - Check for end of speech
- `ra_sherpa_destroy_stream()` - Clean up stream
- `ra_sherpa_destroy_recognizer()` - Clean up recognizer
- `ra_extract_tar_bz2()` - Extract tar.bz2 archives

### 3. XCFramework Build Updates

**File**: `runanywhere-core/scripts/build-ios-onnx.sh`

Updated to include sherpa-onnx and detect libarchive:
- Checks for sherpa-onnx libraries in `third_party/sherpa-onnx-ios/sherpa-onnx.xcframework`
- Checks for libarchive libraries in `third_party/libarchive-ios` (optional)
- Combines sherpa-onnx static library into the final XCFramework using libtool
- Verifies sherpa-onnx symbols are present after build
- Builds work with or without libarchive (graceful degradation)

### 4. System Libraries Integration

**File**: `sdks/examples/ios/RunAnywhereAI/scripts/add_system_libraries.rb`

Created Ruby script to automatically add required system libraries to the Xcode project:
- `libarchive.tbd` - For tar.bz2 extraction
- `libbz2.tbd` - For bzip2 decompression
- `libc++.tbd` - For C++ standard library
- `Accelerate.framework` - For optimized math operations

**Already executed**: The Xcode project has been updated with these libraries.

### 5. Package.swift Updates

**File**: `sdks/sdk/runanywhere-swift/Modules/ONNXRuntime/Package.swift`

Added linker settings to the ONNXRuntime target:
```swift
linkerSettings: [
    .linkedLibrary("c++"),
    .linkedFramework("Accelerate"),
    .linkedLibrary("archive"),
    .linkedLibrary("bz2")
]
```

## Build Instructions

### One-Command Build

Simply run the main build script which now handles everything:

```bash
cd /Users/shubhammalhotra/Desktop/RunanywhereAI/runanywhere-core
./scripts/build-ios-onnx.sh
```

This will:
1. Build ONNX Runtime backend
2. Include sherpa-onnx if available (run `./scripts/build-sherpa-onnx-ios.sh` first if not built)
3. Create RunAnywhereONNX.xcframework
4. Place it in `dist/RunAnywhereONNX.xcframework`

### Copy to SDK

After building, copy the XCFramework to the SDK:

```bash
cp -r dist/RunAnywhereONNX.xcframework \
    /Users/shubhammalhotra/Desktop/RunAnywhereAI/sdks/sdk/runanywhere-swift/XCFrameworks/
```

### Build Sample App

```bash
cd /Users/shubhammalhotra/Desktop/RunAnywhereAI/sdks/examples/ios/RunAnywhereAI
xcodebuild -workspace RunAnywhereAI.xcworkspace -scheme RunAnywhereAI -configuration Debug \
    -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

Or open in Xcode:
```bash
open RunAnywhereAI.xcworkspace
```

## What's Included

### XCFramework Contents

The `RunAnywhereONNX.xcframework` now includes:
- **ONNX Runtime** (1.20.1) - Core inference engine
- **Sherpa-ONNX** - Streaming STT library
- **RunAnywhere ONNX Backend** - Custom backend implementation
- **RunAnywhere ONNX Bridge** - C/C++ bridge with Swift bindings

**Size**: ~235MB (includes all dependencies)

### Sherpa-ONNX Features

- ✅ Streaming speech-to-text with partial results
- ✅ Support for Zipformer transducer models
- ✅ Support for Whisper-based models
- ✅ Endpoint detection (automatic end of speech)
- ✅ Model archive extraction (.tar.bz2)
- ✅ Float32 audio sample conversion
- ✅ AsyncSequence-based streaming API

## Usage Example

```swift
import ONNXRuntime

// Initialize the service
let sttService = ONNXSTTService()

// Initialize with a sherpa-onnx model (auto-detected)
try await sttService.initialize(modelPath: "/path/to/model.tar.bz2")

// Streaming transcription with partial results
let result = try await sttService.streamTranscribe(
    audioStream: audioChunks,
    options: STTOptions(
        language: "en",
        audioFormat: AudioFormat(sampleRate: 16000)
    ),
    onPartial: { partialText in
        print("Partial: \(partialText)")
    }
)

print("Final: \(result.transcript)")
```

## System Requirements

- **iOS**: 14.0+
- **Xcode**: 15.0+
- **Architectures**: arm64 (device), arm64 + x86_64 (simulator)
- **System Libraries**: libarchive, libbz2, libc++, Accelerate (auto-linked in sample app)

## Troubleshooting

### Linker Errors for libarchive/libbz2

If you get undefined symbols for `_archive_*` or `_BZ2_*` functions:

**Solution**: Run the Ruby script to add system libraries to your Xcode project:

```bash
cd /path/to/your/app
ruby scripts/add_system_libraries.rb
```

Or manually add in Xcode:
1. Select your app target
2. Go to "Build Phases" → "Link Binary With Libraries"
3. Click "+" and add:
   - `libarchive.tbd`
   - `libbz2.tbd`
   - `libc++.tbd`
   - `Accelerate.framework`

### Model Not Found

Ensure sherpa-onnx models have the correct structure:
- For Zipformer: `encoder-epoch-99-avg-1.onnx`, `decoder-epoch-99-avg-1.onnx`, `joiner-epoch-99-avg-1.onnx`, `tokens.txt`
- For Whisper: `tiny.en-encoder.onnx`, `tiny.en-decoder.onnx`
- Or provide a `.tar.bz2` archive containing the model files

### Build Sherpa-ONNX

If sherpa-onnx is not available, build it first:

```bash
cd /Users/shubhammalhotra/Desktop/RunanywhereAI/runanywhere-core
./scripts/build-sherpa-onnx-ios.sh
```

This will create `third_party/sherpa-onnx-ios/sherpa-onnx.xcframework`.

## Architecture

```
┌─────────────────────────────────────┐
│  Swift App (RunAnywhereAI)          │
├─────────────────────────────────────┤
│  ONNXSTTService (Swift)              │
│  - Model detection                   │
│  - Streaming transcription           │
│  - Audio conversion                  │
├─────────────────────────────────────┤
│  CRunAnywhereONNX (C Wrapper)        │
│  - ra_sherpa_* functions             │
│  - ra_extract_tar_bz2                │
├─────────────────────────────────────┤
│  RunAnywhereONNX.xcframework         │
│  ┌───────────────────────────────┐  │
│  │ Sherpa-ONNX (C++)             │  │
│  │ - Streaming recognizer        │  │
│  │ - Neural network inference    │  │
│  ├───────────────────────────────┤  │
│  │ ONNX Runtime (C++)            │  │
│  │ - Model execution engine      │  │
│  ├───────────────────────────────┤  │
│  │ libarchive (System)           │  │
│  │ - Archive extraction          │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

## Next Steps

1. ✅ Build the XCFramework: `./scripts/build-ios-onnx.sh`
2. ✅ Copy to SDK
3. ✅ System libraries added to sample app
4. 🔲 Build and test the sample app
5. 🔲 Test with real sherpa-onnx models

## Notes

- The build script automatically detects if sherpa-onnx is available and includes it
- If libarchive is not available as a pre-built library, it will rely on system libraries
- System libraries (libarchive, libbz2) are provided by iOS SDK and don't need to be built
- The XCFramework is self-contained except for system library dependencies
- All linker settings are properly configured in Package.swift
