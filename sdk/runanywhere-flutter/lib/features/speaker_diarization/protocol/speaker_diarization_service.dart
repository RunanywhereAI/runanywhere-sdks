import 'dart:async';

import '../models/speaker_diarization_speaker_info.dart';

/// Protocol for speaker diarization services
/// Defines the contract for identifying and tracking speakers in audio
/// Matches iOS SpeakerDiarizationService from Features/SpeakerDiarization/Protocol/SpeakerDiarizationService.swift
abstract class SpeakerDiarizationService {
  /// The inference framework used by this service
  String get inferenceFramework;

  /// Check if service is ready for processing
  bool get isReady;

  /// Initialize the service
  Future<void> initialize();

  /// Process audio and identify speakers
  /// [samples] Audio samples to analyze
  /// Returns information about the detected speaker
  SpeakerDiarizationSpeakerInfo processAudio(List<double> samples);

  /// Get all identified speakers
  /// Returns array of all speakers detected so far
  List<SpeakerDiarizationSpeakerInfo> getAllSpeakers();

  /// Update the name of a speaker
  /// [speakerId] The ID of the speaker to update
  /// [name] The new name for the speaker
  void updateSpeakerName({required String speakerId, required String name});

  /// Reset the diarization state
  /// Clears all speaker profiles and resets tracking
  void reset();

  /// Cleanup resources
  Future<void> cleanup();
}
