# Changelog

All notable changes to the RunAnywhere LlamaCpp Backend will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.15.9] - 2025-01-11

### Changed
- Updated runanywhere dependency to ^0.15.9 for iOS symbol visibility fix
- See runanywhere 0.15.9 changelog for details on the iOS fix

## [0.15.8] - 2025-01-10

### Added
- Initial public release on pub.dev
- LlamaCpp integration for on-device LLM inference
- GGUF model format support
- Streaming text generation
- Memory-efficient model loading
- Native bindings for iOS and Android

### Features
- High-performance text generation
- Token-by-token streaming output
- Configurable generation parameters (temperature, max tokens, etc.)
- Automatic model management and caching

### Platforms
- iOS 13.0+ support
- Android API 24+ support
