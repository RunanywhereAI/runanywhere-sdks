# Changelog

All notable changes to the RunAnywhere ONNX Backend will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.16.0] - 2026-02-14

### Changed
- Updated runanywhere dependency to ^0.16.0
- Rebuilt native ONNX backend binaries with latest Sherpa-ONNX (v1.12.20 for Android, v1.12.18 for iOS)
- Includes parameter piping fix (#340) and network layer improvements from core SDK

## [0.15.9] - 2025-01-11

### Changed
- Updated runanywhere dependency to ^0.15.9 for iOS symbol visibility fix
- See runanywhere 0.15.9 changelog for details on the iOS fix

## [0.15.8] - 2025-01-10

### Added
- Initial public release on pub.dev
- ONNX Runtime integration for on-device inference
- Speech-to-Text (STT) implementation using Whisper models
- Text-to-Speech (TTS) implementation
- Voice Activity Detection (VAD) implementation using Silero
- Native bindings for iOS and Android

### Features
- Real-time speech transcription
- Neural voice synthesis
- Speech detection for voice interfaces
- Model download and extraction support
- Streaming transcription support

### Platforms
- iOS 13.0+ support
- Android API 24+ support
