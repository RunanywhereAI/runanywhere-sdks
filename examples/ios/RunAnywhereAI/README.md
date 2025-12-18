# RunAnywhereAI

A powerful on-device AI assistant for iOS and macOS. Chat, transcribe speech, generate voice, and have real-time voice conversations — all running privately on your device with no internet required.

<p align="center">
  <a href="https://runanywhere.ai">
    <img src="https://img.shields.io/badge/🌐_Website-green?style=for-the-badge" alt="Visit Website" />
  </a>
</p>

## Features

### 💬 AI Chat
- Interactive conversations with AI models running entirely on your device
- Streaming responses with real-time generation
- Conversation history and message management
- Markdown rendering and code highlighting

### 🎤 Speech to Text
- Real-time voice transcription
- Batch and live transcription modes
- High accuracy speech recognition
- Works completely offline

### 🔊 Text to Speech
- Natural-sounding voice generation
- Adjustable speech rate and pitch
- Multiple voice options
- Instant audio playback

### 🗣️ Voice Assistant
- Full voice conversation experience
- Speak naturally, get spoken responses
- Combines speech recognition, AI, and voice synthesis
- Hands-free interaction

### ⚙️ Privacy First
- All AI processing happens on your device
- No data sent to external servers
- No internet connection required
- Your conversations stay private

## Screenshots

<p align="center">
  <img src="docs/screenshots/chat-interface.png" alt="Chat Interface" width="250"/>
  <img src="docs/screenshots/quiz-flow.png" alt="Model Selection" width="250"/>
  <img src="docs/screenshots/voice-ai.png" alt="Voice AI" width="250"/>
</p>

## Requirements

- **iOS 17.0+** or **macOS 14.0+**
- Apple Silicon recommended for best performance
- ~500MB - 2GB storage per AI model

## Building from Source

### Prerequisites
- Xcode 15.0+
- Swift 5.9+
- macOS 12.0+ for development

### Quick Start

1. Clone the repository:
   ```bash
   git clone https://github.com/RunanywhereAI/sdks.git
   cd examples/ios/RunAnywhereAI/
   ```

2. Open in Xcode:
   ```bash
   open RunAnywhereAI.xcodeproj
   ```

3. Build and run (⌘+R)

### Build Scripts

```bash
# Build and run on simulator
./scripts/build_and_run.sh simulator "iPhone 16 Pro"

# Build and run on device
./scripts/build_and_run.sh device
```

### Xcode 16 Notes

If you encounter sandbox errors during build:
```bash
./scripts/fix_pods_sandbox.sh
```

For Swift macro issues:
```bash
defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES
```

## Architecture

The app follows MVVM architecture with:
- SwiftUI declarative UI
- Centralized model management
- Reactive state with Combine
- Cross-platform iOS/macOS support

## Contributing

See [CONTRIBUTING.md](../../../CONTRIBUTING.md) for development guidelines.

## License

See [LICENSE](../../../LICENSE) for details.
