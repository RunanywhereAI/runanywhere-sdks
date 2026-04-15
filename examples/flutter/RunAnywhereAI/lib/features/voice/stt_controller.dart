import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:path_provider/path_provider.dart';

enum SttMode { batch, live }

enum RecordingState { idle, recording, transcribing }

class SttState {
  const SttState({
    this.mode = SttMode.batch,
    this.recordingState = RecordingState.idle,
    this.transcription = '',
    this.isModelLoaded = false,
    this.modelName,
    this.errorMessage,
  });

  final SttMode mode;
  final RecordingState recordingState;
  final String transcription;
  final bool isModelLoaded;
  final String? modelName;
  final String? errorMessage;

  bool get isRecording => recordingState == RecordingState.recording;
  bool get isTranscribing => recordingState == RecordingState.transcribing;

  SttState copyWith({
    SttMode? mode,
    RecordingState? recordingState,
    String? transcription,
    bool? isModelLoaded,
    String? modelName,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SttState(
      mode: mode ?? this.mode,
      recordingState: recordingState ?? this.recordingState,
      transcription: transcription ?? this.transcription,
      isModelLoaded: isModelLoaded ?? this.isModelLoaded,
      modelName: modelName ?? this.modelName,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final sttControllerProvider =
    NotifierProvider<SttController, SttState>(SttController.new);

class SttController extends Notifier<SttState> {
  final _recorder = AudioRecorder();

  @override
  SttState build() {
    ref.onDispose(_recorder.dispose);
    _syncModelState();
    return const SttState();
  }

  Future<void> _syncModelState() async {
    final loaded = sdk.RunAnywhere.isSTTModelLoaded;
    state = state.copyWith(isModelLoaded: loaded);
  }

  void setMode(SttMode mode) => state = state.copyWith(mode: mode);

  void clearTranscription() => state = state.copyWith(transcription: '');

  Future<void> toggleRecording() async {
    if (state.isRecording) {
      await _stopAndTranscribe();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) return;

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/stt_recording.wav';

      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav),
        path: path,
      );
      state = state.copyWith(
        recordingState: RecordingState.recording,
        clearError: true,
      );
    } on Exception catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  Future<void> _stopAndTranscribe() async {
    try {
      final path = await _recorder.stop();
      if (path == null) return;

      state = state.copyWith(recordingState: RecordingState.transcribing);

      final bytes = await File(path).readAsBytes();
      final text = await sdk.RunAnywhere.transcribe(Uint8List.fromList(bytes));

      state = state.copyWith(
        recordingState: RecordingState.idle,
        transcription: state.transcription.isEmpty
            ? text
            : '${state.transcription}\n$text',
      );
    } on Exception catch (e) {
      state = state.copyWith(
        recordingState: RecordingState.idle,
        errorMessage: e.toString(),
      );
    }
  }
}
