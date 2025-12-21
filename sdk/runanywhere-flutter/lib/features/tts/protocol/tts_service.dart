import 'dart:typed_data';
import '../models/tts_configuration.dart';
import '../models/tts_input.dart';

/// Protocol for TTS services
/// Defines the contract for text-to-speech synthesis
/// Matches iOS TTSService from Features/TTS/Protocol/TTSService.swift
abstract class TTSService {
  /// The inference framework used by this service
  String get inferenceFramework;

  /// Check if service is ready for synthesis
  bool get isReady;

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

  /// Get available voices
  Future<List<TTSVoice>> getAvailableVoices();

  /// Cleanup resources
  Future<void> cleanup();
}

/// Output from TTS synthesis
/// Matches iOS TTSOutput from Features/TTS/Models/TTSOutput.swift
class TTSOutput {
  /// Synthesized audio data
  final Uint8List audioData;

  /// Sample rate of the audio
  final int sampleRate;

  /// Duration of the audio in seconds
  final double duration;

  /// Format of the audio (e.g., 'wav', 'pcm')
  final String format;

  const TTSOutput({
    required this.audioData,
    this.sampleRate = 22050,
    this.duration = 0.0,
    this.format = 'wav',
  });

  /// Check if audio data is empty
  bool get isEmpty => audioData.isEmpty;
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
