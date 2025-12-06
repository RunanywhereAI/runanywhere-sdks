import '../../core/protocols/component/component_configuration.dart';

/// Input for Voice Activity Detection
class VADInput implements ComponentInput {
  /// Audio buffer to process (16-bit PCM samples)
  final List<int>? buffer;

  /// Audio samples (Float32 format, alternative to buffer)
  final List<double>? audioSamples;

  /// Optional override for energy threshold
  final double? energyThresholdOverride;

  const VADInput.fromBuffer(
    this.buffer, {
    this.energyThresholdOverride,
  }) : audioSamples = null;

  const VADInput.fromSamples(
    this.audioSamples, {
    this.energyThresholdOverride,
  }) : buffer = null;

  @override
  void validate() {
    if (buffer == null && audioSamples == null) {
      throw ArgumentError(
        'VADInput must contain either buffer or audioSamples',
      );
    }
    if (energyThresholdOverride != null) {
      if (energyThresholdOverride! < 0 || energyThresholdOverride! > 1.0) {
        throw ArgumentError(
          'Energy threshold override must be between 0 and 1.0',
        );
      }
    }
  }
}

/// Output from Voice Activity Detection
class VADOutput implements ComponentOutput {
  /// Whether speech is detected
  final bool isSpeechDetected;

  /// Audio energy level
  final double energyLevel;

  /// Timestamp of this detection
  @override
  final DateTime timestamp;

  const VADOutput({
    required this.isSpeechDetected,
    required this.energyLevel,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? const _DefaultTimestamp();
}

// Private class to provide default timestamp
class _DefaultTimestamp implements DateTime {
  const _DefaultTimestamp();

  @override
  DateTime add(Duration duration) => DateTime.now().add(duration);

  @override
  int compareTo(DateTime other) => DateTime.now().compareTo(other);

  @override
  DateTime subtract(Duration duration) => DateTime.now().subtract(duration);

  @override
  Duration difference(DateTime other) => DateTime.now().difference(other);

  @override
  bool isAfter(DateTime other) => DateTime.now().isAfter(other);

  @override
  bool isBefore(DateTime other) => DateTime.now().isBefore(other);

  @override
  bool isAtSameMomentAs(DateTime other) =>
      DateTime.now().isAtSameMomentAs(other);

  @override
  int get day => DateTime.now().day;

  @override
  bool get isUtc => DateTime.now().isUtc;

  @override
  int get microsecond => DateTime.now().microsecond;

  @override
  int get microsecondsSinceEpoch => DateTime.now().microsecondsSinceEpoch;

  @override
  int get millisecond => DateTime.now().millisecond;

  @override
  int get millisecondsSinceEpoch => DateTime.now().millisecondsSinceEpoch;

  @override
  int get minute => DateTime.now().minute;

  @override
  int get month => DateTime.now().month;

  @override
  int get second => DateTime.now().second;

  @override
  String get timeZoneName => DateTime.now().timeZoneName;

  @override
  Duration get timeZoneOffset => DateTime.now().timeZoneOffset;

  @override
  int get weekday => DateTime.now().weekday;

  @override
  int get year => DateTime.now().year;

  @override
  int get hour => DateTime.now().hour;

  @override
  String toIso8601String() => DateTime.now().toIso8601String();

  @override
  DateTime toLocal() => DateTime.now().toLocal();

  @override
  DateTime toUtc() => DateTime.now().toUtc();
}
