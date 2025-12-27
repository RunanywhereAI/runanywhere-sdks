import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:runanywhere/features/tts/models/tts_configuration.dart';
import 'package:runanywhere/features/tts/models/tts_input.dart';
import 'package:runanywhere/features/tts/protocol/tts_service.dart';
import 'package:runanywhere/features/tts/tts_output.dart';

/// System TTS Service implementation using flutter_tts
/// Matches iOS SystemTTSService from TTSComponent.swift
class SystemTTSService implements TTSService {
  final FlutterTts _flutterTts = FlutterTts();
  List<TTSVoice> _availableVoicesList = [];
  TTSConfiguration? _configuration;
  bool _isSynthesizing = false;

  SystemTTSService();

  @override
  String get inferenceFramework => 'system';

  @override
  bool get isReady => _configuration != null;

  @override
  bool get isSynthesizing => _isSynthesizing;

  @override
  List<String> get availableVoices =>
      _availableVoicesList.map((v) => v.id).toList();

  @override
  Future<void> initialize(TTSConfiguration configuration) async {
    _configuration = configuration;

    // Configure TTS engine
    await _flutterTts.setSharedInstance(true);

    // Get available voices
    final voices = await _flutterTts.getVoices;
    if (voices is List) {
      _availableVoicesList = voices
          .map((v) {
            if (v is Map) {
              final locale =
                  v['locale']?.toString() ?? v['name']?.toString() ?? 'en-US';
              final name = v['name']?.toString() ?? 'System Voice';
              return TTSVoice(
                id: locale,
                name: name,
                language: locale,
              );
            }
            return null;
          })
          .whereType<TTSVoice>()
          .toList();
    }

    // Set up completion handlers
    _flutterTts.setCompletionHandler(() {
      _isSynthesizing = false;
    });

    _flutterTts.setErrorHandler((msg) {
      _isSynthesizing = false;
    });

    _flutterTts.setStartHandler(() {
      _isSynthesizing = true;
    });
  }

  @override
  Future<TTSOutput> synthesize(TTSInput input) async {
    if (_configuration == null) {
      throw StateError('SystemTTSService not initialized');
    }

    final completer = Completer<void>();
    final startTime = DateTime.now();

    // Set up completion handlers for this synthesis
    _flutterTts.setCompletionHandler(() {
      if (!completer.isCompleted) completer.complete();
    });

    _flutterTts.setErrorHandler((msg) {
      if (!completer.isCompleted) completer.complete();
    });

    // Get text to synthesize
    final text = input.ssml ?? input.text ?? '';

    // Configure voice
    final voice = input.voiceId ?? _configuration!.voice;
    final language = input.language ?? _configuration!.language;

    if (voice != 'system') {
      await _flutterTts.setVoice({
        'name': voice,
        'locale': language,
      });
    } else {
      await _flutterTts.setLanguage(language);
    }

    // Configure speech parameters
    await _flutterTts.setSpeechRate(_configuration!.speakingRate);
    await _flutterTts.setPitch(_configuration!.pitch);
    await _flutterTts.setVolume(_configuration!.volume);

    // Speak the text
    await _flutterTts.speak(text);

    // Wait for synthesis to complete
    await completer.future;

    final processingTime =
        DateTime.now().difference(startTime).inMilliseconds / 1000.0;

    // Note: flutter_tts doesn't provide direct audio data access
    // It plays audio directly through the system
    // For now, return empty data to indicate completion
    return TTSOutput(
      audioData: Uint8List(0),
      format: _configuration!.audioFormat,
      duration: 0.0,
      metadata: SynthesisMetadata(
        voice: voice,
        language: language,
        processingTime: processingTime,
        characterCount: text.length,
      ),
    );
  }

  @override
  Stream<Uint8List> synthesizeStream(TTSInput input) async* {
    // System TTS doesn't support true streaming
    // Just synthesize the complete text and return as single chunk
    final output = await synthesize(input);
    yield output.audioData;
  }

  @override
  Future<void> stop() async {
    await _flutterTts.stop();
    _isSynthesizing = false;
  }

  @override
  Future<List<TTSVoice>> getAvailableVoices() async {
    return _availableVoicesList;
  }

  @override
  Future<void> cleanup() async {
    await _flutterTts.stop();
    _isSynthesizing = false;
    _configuration = null;
  }
}
