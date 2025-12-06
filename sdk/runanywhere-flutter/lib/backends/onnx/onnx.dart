/// ONNX Runtime backend for RunAnywhere Flutter SDK.
///
/// This module provides STT, TTS, VAD capabilities via the native
/// runanywhere-core library using Dart FFI.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:runanywhere/backends/onnx/onnx.dart';
///
/// // Initialize the ONNX backend
/// await OnnxBackend.initialize();
///
/// // Now use STT, TTS, VAD through the standard RunAnywhere API
/// ```
///
/// ## What This Provides
///
/// - **STT (Speech-to-Text)**: Streaming and batch transcription using
///   Sherpa-ONNX with Whisper and Zipformer models
/// - **TTS (Text-to-Speech)**: Neural voice synthesis using VITS models
/// - **VAD (Voice Activity Detection)**: Real-time speech detection
/// - **LLM (Language Models)**: Text generation (future)
///
/// ## Native Library Setup
///
/// Before using this backend, ensure native libraries are set up:
///
/// ```bash
/// # From runanywhere-core directory
/// ./scripts/flutter/setup.sh --platform ios /path/to/runanywhere-flutter
/// ./scripts/flutter/setup.sh --platform android /path/to/runanywhere-flutter
/// ```
library runanywhere_onnx;

// Backend entry point
export 'onnx_backend.dart';

// Adapter
export 'onnx_adapter.dart';

// Services
export 'services/onnx_stt_service.dart';
export 'services/onnx_tts_service.dart';
export 'services/onnx_vad_service.dart';
export 'services/onnx_llm_service.dart';

// Providers
export 'providers/onnx_stt_provider.dart';
export 'providers/onnx_tts_provider.dart';
export 'providers/onnx_vad_provider.dart';
export 'providers/onnx_llm_provider.dart';
