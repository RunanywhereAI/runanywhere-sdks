# Changelog

All notable changes to the RunAnywhere iOS SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.15.0] - 2025-10-17

### Added
- **Integrated Adapter Modules**: LLMSwift, WhisperKitTranscription, and FluidAudioDiarization now available as products from main package
- Users can add single package dependency and select which adapters they need
- No external dependencies required - all adapters included in SDK package

### Fixed
- **Swift Package Manager Support**: Added root-level Package.swift to enable proper SPM consumption from monorepo
- Package can now be added via `https://github.com/RunanywhereAI/sdks` in Xcode and Package.swift

### Changed
- Repository structure updated to support SPM distribution from monorepo
- Nested Package.swift preserved for local development

### Documentation
- Updated README with comprehensive analytics/metrics documentation
- Added streaming API documentation showing StreamingResult usage
- Added model management examples with progress tracking
- Added token estimation utility documentation
- Updated all code examples to show analytics access

## [0.14.0] - 2025-10-15

### Added
- Previous release features and improvements

## [0.13.0] - 2025-10-06

### Added
- Previous release features and improvements

## [0.1.0] - 2025-08-05

### Added
- Initial release of RunAnywhere iOS SDK
- On-device text generation with streaming support
- Voice AI pipeline with VAD, STT, LLM, TTS
- Structured output generation with Generatable protocol
- Model management and lifecycle
- Performance analytics and metrics
- Support for GGUF, Core ML, WhisperKit, and other frameworks

[Unreleased]: https://github.com/RunanywhereAI/sdks/compare/v0.15.0...HEAD
[0.15.0]: https://github.com/RunanywhereAI/sdks/compare/v0.14.0...v0.15.0
[0.14.0]: https://github.com/RunanywhereAI/sdks/compare/v0.13.0...v0.14.0
[0.13.0]: https://github.com/RunanywhereAI/sdks/compare/v0.1.0...v0.13.0
[0.1.0]: https://github.com/RunanywhereAI/sdks/releases/tag/v0.1.0
