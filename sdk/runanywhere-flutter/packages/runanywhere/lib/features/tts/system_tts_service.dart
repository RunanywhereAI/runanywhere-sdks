/// System TTS Service
///
/// Implementation using flutter_tts for platform Text-to-Speech.
/// Matches iOS SystemTTSService from Features/TTS/System/.
library system_tts_service;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:runanywhere/core/module_registry.dart';

/// Configuration for TTS synthesis
class TTSConfiguration {
  final String voice;
  final String language;
  final double speakingRate;
  final double pitch;
  final double volume;
  final String audioFormat;

  const TTSConfiguration({
    this.voice = 'system',
    this.language = 'en-US',
    this.speakingRate = 0.5,
    this.pitch = 1.0,
    this.volume = 1.0,
    this.audioFormat = 'pcm',
  });
}

/// Input for TTS synthesis
class TTSSynthesisInput {
  final String? text;
  final String? ssml;
  final String? voiceId;
  final String? language;

  const TTSSynthesisInput({
    this.text,
    this.ssml,
    this.voiceId,
    this.language,
  });
}

/// Voice information
class TTSVoice {
  final String id;
  final String name;
  final String language;

  const TTSVoice({
    required this.id,
    required this.name,
    required this.language,
  });
}

/// Synthesis metadata
class SynthesisMetadata {
  final String voice;
  final String language;
  final double processingTime;
  final int characterCount;

  const SynthesisMetadata({
    required this.voice,
    required this.language,
    required this.processingTime,
    required this.characterCount,
  });
}

/// Extended TTS output
class TTSSynthesisOutput {
  final Uint8List audioData;
  final String format;
  final double duration;
  final SynthesisMetadata metadata;

  const TTSSynthesisOutput({
    required this.audioData,
    required this.format,
    required this.duration,
    required this.metadata,
  });
}

/// System TTS Service implementation using flutter_tts
/// Matches iOS SystemTTSService from TTSComponent.swift
class SystemTTSService implements TTSService {
  final FlutterTts _flutterTts = FlutterTts();
  List<TTSVoice> _availableVoicesList = [];
  TTSConfiguration? _configuration;
  bool _isSynthesizing = false;

  SystemTTSService();

  String get inferenceFramework => 'system';

  @override
  bool get isReady => _configuration != null;

  bool get isSynthesizing => _isSynthesizing;

  List<String> get availableVoices =>
      _availableVoicesList.map((v) => v.id).toList();

  @override
  Future<void> initialize({String? modelPath}) async {
    _configuration = const TTSConfiguration();

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
    // Note: startTime could be used for telemetry/metrics in the future

    // Set up completion handlers for this synthesis
    _flutterTts.setCompletionHandler(() {
      if (!completer.isCompleted) completer.complete();
    });

    _flutterTts.setErrorHandler((msg) {
      if (!completer.isCompleted) completer.complete();
    });

    // Get text to synthesize
    final text = input.text;

    // Configure voice
    final voice = input.voiceId ?? _configuration!.voice;
    final language = _configuration!.language;

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

    // Note: flutter_tts doesn't provide direct audio data access
    // It plays audio directly through the system
    return TTSOutput(
      audioData: const [],
      format: _configuration!.audioFormat,
      sampleRate: 22050,
    );
  }

  Future<void> stop() async {
    await _flutterTts.stop();
    _isSynthesizing = false;
  }

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
