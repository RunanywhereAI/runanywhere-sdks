import 'dart:typed_data';
import '../models/stt_options.dart';
import '../models/stt_result.dart';

/// Voice Service Protocol
/// Similar to Swift SDK's VoiceService
abstract class VoiceService {
  /// Initialize the service
  Future<void> initialize({required String modelPath});

  /// Transcribe audio
  Future<STTResult> transcribe({
    required Uint8List audioData,
    required STTOptions options,
  });
}

