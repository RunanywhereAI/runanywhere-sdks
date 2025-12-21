import '../../../core/protocols/component/component_configuration.dart';
import '../../../core/types/sdk_component.dart';
import '../protocol/speaker_diarization_error.dart';

/// Configuration for Speaker Diarization component
/// Matches iOS SpeakerDiarizationConfiguration from Features/SpeakerDiarization/Models/SpeakerDiarizationConfiguration.swift
class SpeakerDiarizationConfiguration implements ComponentConfiguration {
  /// Model ID (if using ML-based diarization)
  final String? modelId;

  /// Maximum number of speakers to track (1-100)
  final int maxSpeakers;

  /// Minimum speech duration to consider (seconds)
  final double minSpeechDuration;

  /// Threshold for detecting speaker changes (0.0-1.0)
  final double speakerChangeThreshold;

  /// Enable voice identification features
  final bool enableVoiceIdentification;

  /// Analysis window size (seconds)
  final double windowSize;

  /// Step size for sliding window (seconds)
  final double stepSize;

  const SpeakerDiarizationConfiguration({
    this.modelId,
    this.maxSpeakers = 10,
    this.minSpeechDuration = 0.5,
    this.speakerChangeThreshold = 0.7,
    this.enableVoiceIdentification = false,
    this.windowSize = 2.0,
    this.stepSize = 0.5,
  });

  /// Component type identifier
  SDKComponent get componentType => SDKComponent.speakerDiarization;

  @override
  void validate() {
    if (maxSpeakers <= 0 || maxSpeakers > 100) {
      throw SpeakerDiarizationError.invalidMaxSpeakers(maxSpeakers);
    }
    if (minSpeechDuration <= 0 || minSpeechDuration > 10) {
      throw SpeakerDiarizationError.invalidConfiguration(
        'Min speech duration must be between 0 and 10 seconds',
      );
    }
    if (speakerChangeThreshold < 0 || speakerChangeThreshold > 1.0) {
      throw SpeakerDiarizationError.invalidThreshold(speakerChangeThreshold);
    }
  }

  /// Create a copy with modified values
  SpeakerDiarizationConfiguration copyWith({
    String? modelId,
    int? maxSpeakers,
    double? minSpeechDuration,
    double? speakerChangeThreshold,
    bool? enableVoiceIdentification,
    double? windowSize,
    double? stepSize,
  }) {
    return SpeakerDiarizationConfiguration(
      modelId: modelId ?? this.modelId,
      maxSpeakers: maxSpeakers ?? this.maxSpeakers,
      minSpeechDuration: minSpeechDuration ?? this.minSpeechDuration,
      speakerChangeThreshold:
          speakerChangeThreshold ?? this.speakerChangeThreshold,
      enableVoiceIdentification:
          enableVoiceIdentification ?? this.enableVoiceIdentification,
      windowSize: windowSize ?? this.windowSize,
      stepSize: stepSize ?? this.stepSize,
    );
  }
}

/// Builder pattern for SpeakerDiarizationConfiguration
class SpeakerDiarizationConfigurationBuilder {
  String? _modelId;
  int _maxSpeakers = 10;
  double _minSpeechDuration = 0.5;
  double _speakerChangeThreshold = 0.7;
  bool _enableVoiceIdentification = false;
  double _windowSize = 2.0;
  double _stepSize = 0.5;

  SpeakerDiarizationConfigurationBuilder([String? modelId])
      : _modelId = modelId;

  SpeakerDiarizationConfigurationBuilder modelId(String? value) {
    _modelId = value;
    return this;
  }

  SpeakerDiarizationConfigurationBuilder maxSpeakers(int value) {
    _maxSpeakers = value;
    return this;
  }

  SpeakerDiarizationConfigurationBuilder minSpeechDuration(double value) {
    _minSpeechDuration = value;
    return this;
  }

  SpeakerDiarizationConfigurationBuilder speakerChangeThreshold(double value) {
    _speakerChangeThreshold = value;
    return this;
  }

  SpeakerDiarizationConfigurationBuilder enableVoiceIdentification(bool value) {
    _enableVoiceIdentification = value;
    return this;
  }

  SpeakerDiarizationConfigurationBuilder windowSize(double value) {
    _windowSize = value;
    return this;
  }

  SpeakerDiarizationConfigurationBuilder stepSize(double value) {
    _stepSize = value;
    return this;
  }

  SpeakerDiarizationConfiguration build() {
    return SpeakerDiarizationConfiguration(
      modelId: _modelId,
      maxSpeakers: _maxSpeakers,
      minSpeechDuration: _minSpeechDuration,
      speakerChangeThreshold: _speakerChangeThreshold,
      enableVoiceIdentification: _enableVoiceIdentification,
      windowSize: _windowSize,
      stepSize: _stepSize,
    );
  }
}
