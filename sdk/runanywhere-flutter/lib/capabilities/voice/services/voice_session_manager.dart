/// Voice Session Manager
///
/// Matches iOS VoiceSessionManager.swift from Capabilities/Voice/Services/
library voice_session_manager;
import 'dart:async';


import '../../../foundation/logging/sdk_logger.dart';
import '../../../features/stt/stt_capability.dart' show STTOutput;
import '../models/voice_session.dart';

/// Manages voice session lifecycle
/// Matches iOS VoiceSessionManager from VoiceSessionManager.swift
class VoiceSessionManager {
  final SDKLogger _logger = SDKLogger(category: 'VoiceSessionManager');

  // Session storage
  final Map<String, VoiceSession> _sessions = {};
  String? _activeSessionId;

  VoiceSessionManager();

  /// Initialize the session manager
  Future<void> initialize() async {
    _logger.info('Initializing voice session manager');
    // Any async initialization if needed
  }

  /// Create a new voice session
  VoiceSession createSession(VoiceSessionConfig config) {
    final sessionId = _generateSessionId();
    final session = VoiceSession(
      id: sessionId,
      configuration: config,
      state: VoiceSessionState.idle,
    );

    _sessions[session.id] = session;
    _logger.info('Created voice session: ${session.id}');

    return session;
  }

  /// Start a voice session
  void startSession(String sessionId) {
    final session = _sessions[sessionId];
    if (session != null) {
      session.state = VoiceSessionState.listening;
      session.startTime = DateTime.now();
      _sessions[sessionId] = session;
      _activeSessionId = sessionId;
      _logger.info('Started voice session: $sessionId');
    }
  }

  /// End a voice session
  void endSession(String sessionId) {
    final session = _sessions[sessionId];
    if (session != null) {
      session.state = VoiceSessionState.ended;
      session.endTime = DateTime.now();
      _sessions[sessionId] = session;

      if (_activeSessionId == sessionId) {
        _activeSessionId = null;
      }

      _logger.info('Ended voice session: $sessionId');
    }
  }

  /// Get the active session
  VoiceSession? getActiveSession() {
    if (_activeSessionId == null) return null;
    return _sessions[_activeSessionId];
  }

  /// Get a session by ID
  VoiceSession? getSession(String sessionId) {
    return _sessions[sessionId];
  }

  /// Get all sessions
  List<VoiceSession> getAllSessions() {
    return List.from(_sessions.values);
  }

  /// Update session state
  void updateSessionState(String sessionId, VoiceSessionState state) {
    final session = _sessions[sessionId];
    if (session != null) {
      session.state = state;
      _sessions[sessionId] = session;
      _logger.debug('Updated session $sessionId state to: ${state.value}');
    }
  }

  /// Add transcript to session
  void addTranscript(String sessionId, STTOutput transcript) {
    final session = _sessions[sessionId];
    if (session != null) {
      session.transcripts.add(transcript);
      _sessions[sessionId] = session;
      _logger.debug('Added transcript to session $sessionId');
    }
  }

  /// Clean up old sessions
  void cleanupSessions({required Duration olderThan}) {
    final cutoffDate = DateTime.now().subtract(olderThan);

    final oldSessionIds = <String>[];
    for (final entry in _sessions.entries) {
      final endTime = entry.value.endTime;
      if (endTime != null && endTime.isBefore(cutoffDate)) {
        oldSessionIds.add(entry.key);
      }
    }

    for (final id in oldSessionIds) {
      _sessions.remove(id);
    }

    if (oldSessionIds.isNotEmpty) {
      _logger.info('Cleaned up ${oldSessionIds.length} old sessions');
    }
  }

  /// Check if the session manager is healthy
  bool isHealthy() {
    return true;
  }

  /// Generate a unique session ID
  String _generateSessionId() {
    // Simple UUID-like generation
    final now = DateTime.now().millisecondsSinceEpoch;
    return 'session_$now';
  }
}
