/// Processor generation enumeration.
/// Matches iOS ProcessorGeneration from Capabilities/DeviceCapability/Models/ProcessorInfo.swift
enum ProcessorGeneration {
  generation1('gen1'), // A14, M1
  generation2('gen2'), // A15, M2
  generation3('gen3'), // A16, M3
  generation4('gen4'), // A17 Pro, M4
  generation5('gen5'), // A18, A18 Pro
  unknown('unknown');

  final String rawValue;

  const ProcessorGeneration(this.rawValue);

  static ProcessorGeneration fromRawValue(String value) {
    return ProcessorGeneration.values.firstWhere(
      (g) => g.rawValue == value,
      orElse: () => ProcessorGeneration.unknown,
    );
  }
}

/// Performance tier enumeration.
/// Matches iOS PerformanceTier from Capabilities/DeviceCapability/Models/ProcessorInfo.swift
enum PerformanceTier {
  flagship,
  high,
  medium,
  entry;

  String get rawValue => name;

  static PerformanceTier? fromRawValue(String value) {
    return PerformanceTier.values.cast<PerformanceTier?>().firstWhere(
          (t) => t?.name == value,
          orElse: () => null,
        );
  }
}

/// Processor information.
/// Matches iOS ProcessorInfo from Capabilities/DeviceCapability/Models/ProcessorInfo.swift
class ProcessorInfo {
  /// Chip name (e.g., "Apple A17 Pro")
  final String chipName;

  /// Total core count
  final int coreCount;

  /// Number of performance cores
  final int performanceCores;

  /// Number of efficiency cores
  final int efficiencyCores;

  /// Architecture (e.g., "arm64e", "x86_64")
  final String architecture;

  /// Whether the chip has ARM64E support
  final bool hasARM64E;

  /// Clock frequency in GHz
  final double clockFrequency;

  /// L2 cache size in bytes
  final int l2CacheSize;

  /// L3 cache size in bytes
  final int l3CacheSize;

  /// Number of Neural Engine cores
  final int neuralEngineCores;

  /// Estimated TOPS (trillion operations per second)
  final double estimatedTops;

  /// Processor generation
  final ProcessorGeneration generation;

  /// Whether the chip has a Neural Engine
  final bool hasNeuralEngine;

  ProcessorInfo({
    this.chipName = 'Unknown',
    required this.coreCount,
    this.performanceCores = 0,
    this.efficiencyCores = 0,
    required this.architecture,
    this.hasARM64E = false,
    this.clockFrequency = 0.0,
    this.l2CacheSize = 0,
    this.l3CacheSize = 0,
    this.neuralEngineCores = 0,
    this.estimatedTops = 0.0,
  })  : hasNeuralEngine = neuralEngineCores > 0,
        generation = _determineGeneration(chipName);

  static ProcessorGeneration _determineGeneration(String chipName) {
    if (chipName.contains('A18') || chipName.contains('M4')) {
      return ProcessorGeneration.generation5;
    } else if (chipName.contains('A17') || chipName.contains('M3')) {
      return ProcessorGeneration.generation4;
    } else if (chipName.contains('A16') || chipName.contains('M2')) {
      return ProcessorGeneration.generation3;
    } else if (chipName.contains('A15') || chipName.contains('M1')) {
      return ProcessorGeneration.generation2;
    } else if (chipName.contains('A14')) {
      return ProcessorGeneration.generation1;
    } else {
      return ProcessorGeneration.unknown;
    }
  }

  /// Whether this is an Apple Silicon processor
  bool get isAppleSilicon =>
      architecture.toLowerCase().contains('arm') && hasARM64E;

  /// Whether this is an Intel processor
  bool get isIntel => architecture.toLowerCase().contains('x86');

  /// Total cache size
  int get totalCacheSize => l2CacheSize + l3CacheSize;

  /// Performance tier based on estimated TOPS
  PerformanceTier get performanceTier {
    if (estimatedTops >= 35) return PerformanceTier.flagship;
    if (estimatedTops >= 15) return PerformanceTier.high;
    if (estimatedTops >= 10) return PerformanceTier.medium;
    return PerformanceTier.entry;
  }

  /// Recommended batch size based on performance tier
  int get recommendedBatchSize {
    switch (performanceTier) {
      case PerformanceTier.flagship:
        return 8;
      case PerformanceTier.high:
        return 4;
      case PerformanceTier.medium:
        return 2;
      case PerformanceTier.entry:
        return 1;
    }
  }

  /// Whether the processor supports concurrent inference
  bool get supportsConcurrentInference =>
      performanceCores >= 4 && neuralEngineCores >= 16;

  /// Create from JSON map
  factory ProcessorInfo.fromJson(Map<String, dynamic> json) {
    return ProcessorInfo(
      chipName: json['chipName'] as String? ?? 'Unknown',
      coreCount: (json['coreCount'] as num?)?.toInt() ?? 0,
      performanceCores: (json['performanceCores'] as num?)?.toInt() ?? 0,
      efficiencyCores: (json['efficiencyCores'] as num?)?.toInt() ?? 0,
      architecture: json['architecture'] as String? ?? 'unknown',
      hasARM64E: json['hasARM64E'] as bool? ?? false,
      clockFrequency: (json['clockFrequency'] as num?)?.toDouble() ?? 0.0,
      l2CacheSize: (json['l2CacheSize'] as num?)?.toInt() ?? 0,
      l3CacheSize: (json['l3CacheSize'] as num?)?.toInt() ?? 0,
      neuralEngineCores: (json['neuralEngineCores'] as num?)?.toInt() ?? 0,
      estimatedTops: (json['estimatedTops'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'chipName': chipName,
      'coreCount': coreCount,
      'performanceCores': performanceCores,
      'efficiencyCores': efficiencyCores,
      'architecture': architecture,
      'hasARM64E': hasARM64E,
      'clockFrequency': clockFrequency,
      'l2CacheSize': l2CacheSize,
      'l3CacheSize': l3CacheSize,
      'neuralEngineCores': neuralEngineCores,
      'estimatedTops': estimatedTops,
      'generation': generation.rawValue,
      'hasNeuralEngine': hasNeuralEngine,
    };
  }
}
