import 'dart:async';

import 'package:runanywhere/core/capabilities_base/base_capability.dart';
import 'package:runanywhere/core/types/sdk_component.dart';
import 'package:runanywhere/features/speaker_diarization/models/speaker_diarization_configuration.dart';
import 'package:runanywhere/features/speaker_diarization/models/speaker_diarization_speaker_info.dart';
import 'package:runanywhere/features/speaker_diarization/protocol/speaker_diarization_error.dart';
import 'package:runanywhere/features/speaker_diarization/protocol/speaker_diarization_service.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';

/// Speaker Diarization capability for identifying and tracking speakers
/// Matches iOS SpeakerDiarizationCapability from Features/SpeakerDiarization/SpeakerDiarizationCapability.swift
class SpeakerDiarizationCapability
    extends BaseCapability<SpeakerDiarizationService> {
  final SDKLogger _logger = SDKLogger(category: 'SpeakerDiarizationCapability');

  /// Whether diarization is initialized
  bool _isConfigured = false;

  /// Get the configuration
  SpeakerDiarizationConfiguration get speakerDiarizationConfiguration =>
      configuration as SpeakerDiarizationConfiguration;

  SpeakerDiarizationCapability({
    SpeakerDiarizationConfiguration? configuration,
    super.serviceContainer,
  }) : super(
            configuration:
                configuration ?? const SpeakerDiarizationConfiguration());

  @override
  SDKComponent get componentType => SDKComponent.speakerDiarization;

  @override
  Future<SpeakerDiarizationService> createService() async {
    // Service creation would be handled by ServiceRegistry
    // This is a placeholder - actual implementation would create from registry
    throw SpeakerDiarizationError.notInitialized();
  }

  @override
  Future<void> initializeService() async {
    _logger.info('Initializing Speaker Diarization');
    _isConfigured = true;
    _logger.info('Speaker Diarization initialized successfully');
  }

  /// Check if the capability is ready
  @override
  bool get isReady => _isConfigured && service?.isReady == true;

  /// Process audio and identify speaker
  /// [samples] Audio samples to analyze
  /// Returns information about the detected speaker
  Future<SpeakerDiarizationSpeakerInfo> processAudio(
      List<double> samples) async {
    final svc = service;
    if (svc == null) {
      throw SpeakerDiarizationError.notInitialized();
    }

    _logger.debug('Processing audio for speaker identification');
    return svc.processAudio(samples);
  }

  /// Get all identified speakers
  /// Returns array of all speakers detected so far
  List<SpeakerDiarizationSpeakerInfo> getAllSpeakers() {
    final svc = service;
    if (svc == null) {
      throw SpeakerDiarizationError.notInitialized();
    }

    return svc.getAllSpeakers();
  }

  /// Update speaker name
  /// [speakerId] The speaker ID to update
  /// [name] The new name for the speaker
  Future<void> updateSpeakerName({
    required String speakerId,
    required String name,
  }) async {
    final svc = service;
    if (svc == null) {
      throw SpeakerDiarizationError.notInitialized();
    }

    _logger.info('Updating speaker name: $speakerId -> $name');
    svc.updateSpeakerName(speakerId: speakerId, name: name);
  }

  /// Reset the diarization state
  /// Clears all speaker profiles and resets tracking
  Future<void> reset() async {
    final svc = service;
    if (svc == null) {
      throw SpeakerDiarizationError.notInitialized();
    }

    _logger.info('Resetting speaker diarization state');
    svc.reset();
  }

  @override
  Future<void> performCleanup() async {
    _logger.info('Cleaning up Speaker Diarization');
    await service?.cleanup();
    _isConfigured = false;
  }
}
