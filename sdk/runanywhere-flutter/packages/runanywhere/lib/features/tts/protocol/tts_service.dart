import 'dart:async';
import 'dart:typed_data';
import 'package:runanywhere/features/tts/models/tts_configuration.dart';
import 'package:runanywhere/features/tts/models/tts_input.dart';
import 'package:runanywhere/features/tts/tts_output.dart';

/// Protocol for TTS services
/// Defines the contract for text-to-speech synthesis
/// Matches iOS TTSService from Features/TTS/Protocol/TTSService.swift
abstract class TTSService {
  /// The inference framework used by this service.
  /// Required for analytics and performance tracking.
  /// Matches iOS TTSService.inferenceFramework property.
  String get inferenceFramework;

  /// Check if service is ready for synthesis
  bool get isReady;

  /// Whether currently synthesizing.
  /// Matches iOS TTSService.isSynthesizing property.
  bool get isSynthesizing;

  /// List of available voices.
  /// Matches iOS TTSService.availableVoices property.
  List<String> get availableVoices;

  /// Initialize the service with configuration
  Future<void> initialize(TTSConfiguration configuration);

  /// Synthesize text to audio
  /// [input] The text/SSML to synthesize
  /// Returns synthesized audio data
  Future<TTSOutput> synthesize(TTSInput input);

  /// Synthesize text to audio stream
  /// [input] The text/SSML to synthesize
  /// Returns stream of audio chunks
  Stream<Uint8List> synthesizeStream(TTSInput input);

  /// Stop current synthesis.
  /// Matches iOS TTSService.stop() method.
  Future<void> stop();

  /// Get available voices with detailed information
  Future<List<TTSVoice>> getAvailableVoices();

  /// Cleanup resources
  Future<void> cleanup();
}

/// Information about a TTS voice
/// Matches iOS TTSVoice
class TTSVoice {
  /// Unique identifier for the voice
  final String id;

  /// Display name of the voice
  final String name;

  /// Language code (e.g., 'en-US')
  final String language;

  /// Gender of the voice
  final TTSVoiceGender gender;

  /// Quality level of the voice
  final TTSVoiceQuality quality;

  const TTSVoice({
    required this.id,
    required this.name,
    required this.language,
    this.gender = TTSVoiceGender.neutral,
    this.quality = TTSVoiceQuality.standard,
  });
}

/// Voice gender options
enum TTSVoiceGender {
  male,
  female,
  neutral,
}

/// Voice quality levels
enum TTSVoiceQuality {
  standard,
  enhanced,
  neural,
}
