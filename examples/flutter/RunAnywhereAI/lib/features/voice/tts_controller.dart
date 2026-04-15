import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;

class TtsState {
  const TtsState({
    this.isModelLoaded = false,
    this.modelName,
    this.isSynthesizing = false,
    this.isPlaying = false,
    this.speechRate = 1.0,
    this.audioData,
    this.durationMs,
    this.sampleRate,
    this.errorMessage,
  });

  final bool isModelLoaded;
  final String? modelName;
  final bool isSynthesizing;
  final bool isPlaying;
  final double speechRate;
  final Float32List? audioData;
  final int? durationMs;
  final int? sampleRate;
  final String? errorMessage;

  bool get hasAudio => audioData != null;

  TtsState copyWith({
    bool? isModelLoaded,
    String? modelName,
    bool? isSynthesizing,
    bool? isPlaying,
    double? speechRate,
    Float32List? audioData,
    int? durationMs,
    int? sampleRate,
    String? errorMessage,
    bool clearError = false,
    bool clearAudio = false,
  }) {
    return TtsState(
      isModelLoaded: isModelLoaded ?? this.isModelLoaded,
      modelName: modelName ?? this.modelName,
      isSynthesizing: isSynthesizing ?? this.isSynthesizing,
      isPlaying: isPlaying ?? this.isPlaying,
      speechRate: speechRate ?? this.speechRate,
      audioData: clearAudio ? null : (audioData ?? this.audioData),
      durationMs: clearAudio ? null : (durationMs ?? this.durationMs),
      sampleRate: clearAudio ? null : (sampleRate ?? this.sampleRate),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final ttsControllerProvider =
    NotifierProvider<TtsController, TtsState>(TtsController.new);

class TtsController extends Notifier<TtsState> {
  final _player = AudioPlayer();

  @override
  TtsState build() {
    ref.onDispose(_player.dispose);
    _player.onPlayerStateChanged.listen((playerState) {
      state = state.copyWith(
        isPlaying: playerState == PlayerState.playing,
      );
    });
    _syncModelState();
    return const TtsState();
  }

  Future<void> _syncModelState() async {
    final loaded = sdk.RunAnywhere.isTTSVoiceLoaded;
    state = state.copyWith(isModelLoaded: loaded);
  }

  void setSpeechRate(double rate) => state = state.copyWith(speechRate: rate);

  Future<void> synthesize(String text) async {
    if (text.trim().isEmpty || state.isSynthesizing) return;

    state = state.copyWith(
      isSynthesizing: true,
      clearError: true,
      clearAudio: true,
    );

    try {
      final result = await sdk.RunAnywhere.synthesize(
        text,
        rate: state.speechRate,
      );

      state = state.copyWith(
        isSynthesizing: false,
        audioData: result.samples,
        durationMs: result.durationMs,
        sampleRate: result.sampleRate,
      );
    } on Exception catch (e) {
      state = state.copyWith(
        isSynthesizing: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> togglePlayback() async {
    if (state.isPlaying) {
      await _player.stop();
    } else if (state.audioData != null) {
      final wavBytes = _float32ToWav(
        state.audioData!,
        state.sampleRate ?? 22050,
      );
      await _player.play(BytesSource(wavBytes));
    }
  }

  Uint8List _float32ToWav(Float32List samples, int sampleRate) {
    final numSamples = samples.length;
    final byteRate = sampleRate * 2;
    final dataSize = numSamples * 2;
    final fileSize = 36 + dataSize;

    final buffer = ByteData(44 + dataSize);
    // RIFF header
    buffer.setUint8(0, 0x52); // R
    buffer.setUint8(1, 0x49); // I
    buffer.setUint8(2, 0x46); // F
    buffer.setUint8(3, 0x46); // F
    buffer.setUint32(4, fileSize, Endian.little);
    buffer.setUint8(8, 0x57); // W
    buffer.setUint8(9, 0x41); // A
    buffer.setUint8(10, 0x56); // V
    buffer.setUint8(11, 0x45); // E
    // fmt chunk
    buffer.setUint8(12, 0x66); // f
    buffer.setUint8(13, 0x6D); // m
    buffer.setUint8(14, 0x74); // t
    buffer.setUint8(15, 0x20); // ' '
    buffer.setUint32(16, 16, Endian.little); // chunk size
    buffer.setUint16(20, 1, Endian.little); // PCM
    buffer.setUint16(22, 1, Endian.little); // mono
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, byteRate, Endian.little);
    buffer.setUint16(32, 2, Endian.little); // block align
    buffer.setUint16(34, 16, Endian.little); // bits per sample
    // data chunk
    buffer.setUint8(36, 0x64); // d
    buffer.setUint8(37, 0x61); // a
    buffer.setUint8(38, 0x74); // t
    buffer.setUint8(39, 0x61); // a
    buffer.setUint32(40, dataSize, Endian.little);

    for (var i = 0; i < numSamples; i++) {
      final sample = (samples[i] * 32767).clamp(-32768, 32767).toInt();
      buffer.setInt16(44 + i * 2, sample, Endian.little);
    }

    return buffer.buffer.asUint8List();
  }
}
