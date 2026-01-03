// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../foundation/logging/sdk_logger.dart';
import 'ffi_types.dart';
import 'platform_loader.dart';

/// Voice agent bridge for C++ voice agent operations.
/// Matches Swift's `CppBridge+VoiceAgent.swift`.
class DartBridgeVoiceAgent {
  DartBridgeVoiceAgent._();

  static final _logger = SDKLogger('DartBridge.VoiceAgent');
  static final DartBridgeVoiceAgent instance = DartBridgeVoiceAgent._();

  /// Active voice sessions
  final Map<String, _VoiceSession> _activeSessions = {};

  /// Create a new voice session
  Future<String?> createSession({
    String? configJson,
    void Function(String transcript, bool isFinal)? onTranscript,
    void Function(List<double> audio)? onAudio,
    void Function(String error)? onError,
  }) async {
    try {
      final lib = PlatformLoader.load();
      final createFn = lib.lookupFunction<
          Pointer<Utf8> Function(Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Utf8>)>('rac_voice_agent_create_session');

      final configPtr = (configJson ?? '{}').toNativeUtf8();
      try {
        final result = createFn(configPtr);
        if (result == nullptr) return null;

        final sessionId = result.toDartString();

        _activeSessions[sessionId] = _VoiceSession(
          sessionId: sessionId,
          onTranscript: onTranscript,
          onAudio: onAudio,
          onError: onError,
        );

        return sessionId;
      } finally {
        calloc.free(configPtr);
      }
    } catch (e) {
      _logger.debug('rac_voice_agent_create_session not available: $e');
      return null;
    }
  }

  /// Start a voice session
  Future<bool> startSession(String sessionId) async {
    try {
      final lib = PlatformLoader.load();
      final startFn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)>('rac_voice_agent_start_session');

      final idPtr = sessionId.toNativeUtf8();
      try {
        final result = startFn(idPtr);
        return result == RacResultCode.success;
      } finally {
        calloc.free(idPtr);
      }
    } catch (e) {
      _logger.debug('rac_voice_agent_start_session not available: $e');
      return false;
    }
  }

  /// Stop a voice session
  Future<bool> stopSession(String sessionId) async {
    try {
      final lib = PlatformLoader.load();
      final stopFn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)>('rac_voice_agent_stop_session');

      final idPtr = sessionId.toNativeUtf8();
      try {
        final result = stopFn(idPtr);
        return result == RacResultCode.success;
      } finally {
        calloc.free(idPtr);
      }
    } catch (e) {
      _logger.debug('rac_voice_agent_stop_session not available: $e');
      return false;
    }
  }

  /// Destroy a voice session
  Future<void> destroySession(String sessionId) async {
    _activeSessions.remove(sessionId);

    try {
      final lib = PlatformLoader.load();
      final destroyFn = lib.lookupFunction<
          Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)>('rac_voice_agent_destroy_session');

      final idPtr = sessionId.toNativeUtf8();
      try {
        destroyFn(idPtr);
      } finally {
        calloc.free(idPtr);
      }
    } catch (e) {
      _logger.debug('rac_voice_agent_destroy_session not available: $e');
    }
  }

  /// Send text to the voice agent
  Future<bool> sendText(String sessionId, String text) async {
    try {
      final lib = PlatformLoader.load();
      final sendFn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
          int Function(Pointer<Utf8>, Pointer<Utf8>)>('rac_voice_agent_send_text');

      final idPtr = sessionId.toNativeUtf8();
      final textPtr = text.toNativeUtf8();
      try {
        final result = sendFn(idPtr, textPtr);
        return result == RacResultCode.success;
      } finally {
        calloc.free(idPtr);
        calloc.free(textPtr);
      }
    } catch (e) {
      _logger.debug('rac_voice_agent_send_text not available: $e');
      return false;
    }
  }

  /// Interrupt the voice agent
  Future<bool> interrupt(String sessionId) async {
    try {
      final lib = PlatformLoader.load();
      final interruptFn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)>('rac_voice_agent_interrupt');

      final idPtr = sessionId.toNativeUtf8();
      try {
        final result = interruptFn(idPtr);
        return result == RacResultCode.success;
      } finally {
        calloc.free(idPtr);
      }
    } catch (e) {
      _logger.debug('rac_voice_agent_interrupt not available: $e');
      return false;
    }
  }

  /// Get active session count
  int get activeSessionCount => _activeSessions.length;
}

class _VoiceSession {
  final String sessionId;
  final void Function(String transcript, bool isFinal)? onTranscript;
  final void Function(List<double> audio)? onAudio;
  final void Function(String error)? onError;

  _VoiceSession({
    required this.sessionId,
    this.onTranscript,
    this.onAudio,
    this.onError,
  });
}
