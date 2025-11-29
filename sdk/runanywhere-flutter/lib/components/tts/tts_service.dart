import 'dart:async';
import 'dart:typed_data';
import 'tts_options.dart';

/// Protocol for text-to-speech services
/// Matches iOS TTSService protocol from TTSComponent.swift
abstract class TTSService {
  /// Initialize the TTS service
  Future<void> initialize();

  /// Synthesize text to audio
  Future<Uint8List> synthesize({
    required String text,
    required TTSOptions options,
  });

  /// Stream synthesis for long text
  /// Calls onChunk for each audio chunk as it becomes available
  Future<void> synthesizeStream({
    required String text,
    required TTSOptions options,
    required void Function(Uint8List chunk) onChunk,
  });

  /// Stop current synthesis
  void stop();

  /// Check if currently synthesizing
  bool get isSynthesizing;

  /// Get available voices
  List<String> get availableVoices;

  /// Cleanup resources
  Future<void> cleanup();
}
