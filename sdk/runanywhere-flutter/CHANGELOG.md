# Changelog

All notable changes to the RunAnywhere Flutter SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.15.8] - 2025-01-XX

### Added
- Initial Flutter SDK release
- Core architecture with component-based design
- Text generation with streaming support
- Model management (load, download, list)
- Voice operations (transcription)
- Event system with Streams
- Secure storage for API keys
- Logging system
- Error handling

### Features
- SDK initialization API
- Text generation API (`generate`, `generateStream`, `chat`)
- Model management API (`loadModel`, `availableModels`, `currentModel`)
- Voice transcription API (`transcribe`)
- Event bus for reactive programming
- Service container for dependency injection
- Module registry for plugin architecture

