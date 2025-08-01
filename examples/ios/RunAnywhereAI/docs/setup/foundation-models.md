# Foundation Models Framework Setup Guide

## Overview
Apple's Foundation Models framework provides on-device AI capabilities with a ~3B parameter language model. It was announced at WWDC 2025 and is currently in beta.

## Requirements

### Development Environment
- **Xcode**: 26.0 beta or later (Download from [developer.apple.com](https://developer.apple.com))
- **macOS**: 26 Tahoe or later (required for Xcode 26)
- **Swift**: 6.1 or later

### Deployment Requirements
- **iOS**: 26.0 beta or later
- **Devices**: iPhone 15 Pro or later (A17 Pro chip minimum)
- **Apple Intelligence**: Must be enabled on device

## Current Status (July 2025)
You are currently using:
- ✅ iOS 26.0 beta (Device compatible)
- ❌ Xcode 16.4 (Needs Xcode 26 beta)

## Setup Instructions

### 1. Download Xcode 26 Beta
1. Go to [developer.apple.com](https://developer.apple.com)
2. Sign in with your Apple Developer account
3. Navigate to Downloads → Beta Software
4. Download Xcode 26 beta

### 2. Install macOS 26 Tahoe (if needed)
Xcode 26 requires macOS 26 Tahoe. Check your Mac compatibility and install if needed.

### 3. Enable Foundation Models Import
Once you have Xcode 26, uncomment the import in `FoundationModelsService.swift`:

```swift
#if canImport(FoundationModels)
import FoundationModels
#endif
```

### 4. Basic Usage
```swift
import FoundationModels

// Check availability
let systemModel = SystemLanguageModel.default
guard systemModel.isAvailable else {
    throw LLMError.notAvailable
}

// Create session
let session = LanguageModelSession()

// Generate response
let prompt = Prompt("Hello, how are you?")
let response = try await session.respond(to: prompt)
print(response.text)
```

### 5. Streaming Responses
```swift
let stream = session.streamResponse(to: prompt)
for try await partialText in stream {
    print(partialText, terminator: "")
}
```

## Features
- **On-device processing**: No internet required
- **Privacy-focused**: Data stays on device
- **~3B parameters**: Optimized for mobile
- **Streaming support**: Real-time responses
- **Tool calling**: Advanced capabilities
- **Guided generation**: Structured outputs

## Limitations
- Not designed for world knowledge
- Limited to general reasoning tasks
- Requires recent Apple Silicon devices
- Beta API may change

## Troubleshooting

### "Foundation Models not available"
- Ensure device has A17 Pro or newer chip
- Check that Apple Intelligence is enabled
- Verify iOS 26+ is installed

### "Cannot import FoundationModels"
- Update to Xcode 26 beta
- Clean build folder
- Restart Xcode

### Build Errors
- Ensure minimum deployment target is iOS 26.0
- Update Swift version to 6.1+
- Check that macOS 26 Tahoe is installed

## Alternative Frameworks
While waiting for Xcode 26, you can use:
- **Core ML**: Available now, works with Xcode 16
- **MLX**: High performance on Apple Silicon
- **llama.cpp**: Cross-platform compatibility

## Resources
- [WWDC 2025 Session](https://developer.apple.com/videos/play/wwdc2025/10210/)
- [Foundation Models Documentation](https://developer.apple.com/documentation/foundationmodels)
- [Apple Machine Learning](https://developer.apple.com/machine-learning/)
