# Changelog

All notable changes to the RunAnywhere Flutter SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.16.0] - 2026-02-14

### Added
- **API Configuration**: Custom API configuration management for flexible backend routing
- **Keychain Store**: Secure credential storage capabilities via platform keychain
- **Dev Mode**: Development configuration support for local testing and debugging

### Fixed
- **Parameter Piping**: Fixed parameter propagation through SDK layers (#340)
- **Network Layer**: Resolved authentication and dev config networking issues
- **Simulator Scripts**: Fixed build scripts for iOS simulator targets
- **Android Models**: Updated model support handling for Android platform

### Changed
- Updated native binaries (RACommons, RABackendLLAMACPP, RABackendONNX) to latest builds
- Addressed PR #309 review feedback with critical fixes

## [0.15.11] - 2025-01-11

### Fixed
- **iOS**: Updated RACommons.xcframework to v0.1.5 with correct symbol visibility
  - The v0.1.4 xcframework had symbols that became local during linking
  - v0.1.5 xcframework properly exports all symbols as global
  - Combined with `DynamicLibrary.executable()` from 0.15.10, iOS now works correctly

## [0.15.10] - 2025-01-11

### Fixed
- **iOS**: Fixed symbol lookup by using `DynamicLibrary.executable()` instead of `DynamicLibrary.process()`
  - `process()` uses `dlsym(RTLD_DEFAULT)` which only finds GLOBAL symbols
  - `executable()` can find both global and LOCAL symbols in the main binary
  - With static linkage, xcframework symbols become local - this is the correct fix

## [0.15.9] - 2025-01-11

### Fixed
- **iOS**: Added linker flags (partial fix, superseded by 0.15.10)

### Important
- **iOS Podfile Configuration Required**: Users must configure their Podfile with `use_frameworks! :linkage => :static` for the SDK to work correctly. See README.md for complete setup instructions.

## [0.15.8] - 2025-01-10

### Added
- Initial public release on pub.dev
- Core SDK infrastructure with modular backend support
- Event bus for component communication
- Service container for dependency injection
- Native FFI bridge for on-device AI inference
- Audio capture and playback management
- Model download and management system
- Voice session management
- Structured output handling for LLM responses

### Features
- Speech-to-Text (STT) interface
- Text-to-Speech (TTS) interface with system TTS fallback
- Voice Activity Detection (VAD) interface
- LLM text generation interface with streaming support
- Voice agent orchestration
- Secure storage for API keys and credentials

### Platforms
- iOS 13.0+ support
- Android API 24+ support
