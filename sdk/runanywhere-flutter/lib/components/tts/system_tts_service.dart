import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_tts/flutter_tts.dart';
import 'tts_service.dart';
import 'tts_options.dart';

/// System TTS Service implementation using flutter_tts
/// Matches iOS SystemTTSService from TTSComponent.swift
class SystemTTSService implements TTSService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSynthesizing = false;
  List<String> _availableVoices = [];

  SystemTTSService();

  @override
  Future<void> initialize({String? modelPath}) async {
    // modelPath is ignored for system TTS
    // Configure TTS engine
    await _flutterTts.setSharedInstance(true);

    // Get available voices
    final voices = await _flutterTts.getVoices;
    if (voices is List) {
      _availableVoices = voices
          .map((v) {
            if (v is Map) {
              return v['locale']?.toString() ?? v['name']?.toString() ?? '';
            }
            return v.toString();
          })
          .where((v) => v.isNotEmpty)
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
  Future<Uint8List> synthesize({
    required String text,
    required TTSOptions options,
  }) async {
    final completer = Completer<void>();

    // Set up completion handlers for this synthesis
    _flutterTts.setCompletionHandler(() {
      _isSynthesizing = false;
      if (!completer.isCompleted) completer.complete();
    });

    _flutterTts.setErrorHandler((msg) {
      _isSynthesizing = false;
      if (!completer.isCompleted) completer.complete();
    });

    // Configure voice
    if (options.voice != null && options.voice != 'system') {
      await _flutterTts.setVoice({
        'name': options.voice!,
        'locale': options.language,
      });
    } else {
      await _flutterTts.setLanguage(options.language);
    }

    // Configure speech parameters
    await _flutterTts.setSpeechRate(options.rate);
    await _flutterTts.setPitch(options.pitch);
    await _flutterTts.setVolume(options.volume);

    // Speak the text
    _isSynthesizing = true;
    await _flutterTts.speak(text);

    // Wait for synthesis to complete
    await completer.future;

    // Note: flutter_tts doesn't provide direct audio data access
    // It plays audio directly through the system
    // For now, return empty data to indicate completion
    // In a full implementation, we would need platform-specific code
    // to capture the audio data
    return Uint8List(0);
  }

  @override
  Future<void> synthesizeStream({
    required String text,
    required TTSOptions options,
    required void Function(Uint8List chunk) onChunk,
  }) async {
    // System TTS doesn't support true streaming
    // Just synthesize the complete text
    await synthesize(text: text, options: options);
    // Signal completion with empty data
    onChunk(Uint8List(0));
  }

  @override
  void stop() {
    _flutterTts.stop();
    _isSynthesizing = false;
  }

  @override
  bool get isSynthesizing => _isSynthesizing;

  @override
  List<String> get availableVoices => _availableVoices;

  @override
  Future<void> cleanup() async {
    stop();
    // flutter_tts doesn't require explicit cleanup
  }
}
