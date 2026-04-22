/// Voice Session Handle
///
/// v2 close-out Phase 12 (P2-7). The pre-Phase-12 implementation was a
/// ~400-LOC class that re-implemented audio capture management,
/// RMS-based VAD, silence-window detection, and the full STT → LLM → TTS
/// pipeline in Dart — duplicating what the C++ voice agent already does
/// (rac_voice_agent_*) and what the Wave C `VoiceAgentStreamAdapter`
/// (lib/adapters/voice_agent_stream_adapter.dart) exposes idiomatically
/// as a `Stream<VoiceEvent>`.
///
/// All of that orchestration is gone. New code MUST use:
///
///     final adapter = VoiceAgentStreamAdapter(handle);
///     await for (final event in adapter.stream()) handleEvent(event);
///
/// This file is kept as a thin deprecation shell so existing call sites
/// compile. The `events` stream emits a one-time deprecation warning
/// + `started` + `stopped` and that's it.
library voice_session_handle;

import 'dart:async';
import 'dart:typed_data';

import 'package:runanywhere/capabilities/voice/models/voice_session.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';

@Deprecated('Use VoiceAgentStreamAdapter from lib/adapters/voice_agent_stream_adapter.dart')
class VoiceSessionHandle {
  final SDKLogger _logger = SDKLogger('VoiceSessionHandle');
  final VoiceSessionConfig config;

  bool _isRunning = false;
  final StreamController<VoiceSessionEvent> _eventController =
      StreamController<VoiceSessionEvent>.broadcast();

  // Source-compat: the constructor still accepts the old positional/named
  // parameters so existing call sites compile. The callbacks are ignored —
  // orchestration moved to the C++ voice agent.
  VoiceSessionHandle({
    VoiceSessionConfig? config,
    Future<VoiceAgentProcessResult> Function(Uint8List audioData)? processAudioCallback,
    @Deprecated('Permission handled by C++ voice agent')
    Future<bool> Function()? requestPermissionCallback,
    Future<bool> Function()? isVoiceAgentReadyCallback,
    Future<void> Function()? initializeVoiceAgentCallback,
  }) : config = config ?? VoiceSessionConfig.defaultConfig {
    // The 4 callbacks are dropped on the floor; the C++ voice agent owns
    // these concerns now. Ignore-warning suppression matches what existing
    // callers expect when they pass these.
    // ignore_for_file: unused_local_variable
  }

  Stream<VoiceSessionEvent> get events => _eventController.stream;
  bool get isRunning => _isRunning;

  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;
    _logger.warning(
        'VoiceSessionHandle.start: orchestration deleted in v2 close-out '
        'Phase 12. Migrate to VoiceAgentStreamAdapter(handle).stream().');
    _eventController.add(const VoiceSessionEvent.started());
  }

  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;
    _eventController.add(const VoiceSessionEvent.stopped());
    await _eventController.close();
  }

  /// Preserved for source compatibility — no-op since the orchestrator
  /// (and the audio capture/playback components it owned) is gone.
  Future<void> sendNow() async {
    _logger.fine('sendNow: no-op since v2 close-out — handled by C++ voice agent.');
  }

  Future<void> resumeListening() async {
    _logger.fine('resumeListening: no-op since v2 close-out.');
  }

  void interruptPlayback() {
    _logger.fine('interruptPlayback: no-op since v2 close-out.');
  }
}
