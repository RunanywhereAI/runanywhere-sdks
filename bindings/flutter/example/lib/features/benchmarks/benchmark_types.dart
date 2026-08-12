import 'package:runanywhere/runanywhere.dart' as sdk;

/// Data models for the benchmarking suite.
///
/// Mirrors iOS `Features/Benchmarks/Models/BenchmarkTypes.swift`. All types
/// are JSON-serializable so [BenchmarkRun]s can persist through the store.
/// VLM is an optional follow-up (parity plan §4.7), so only LLM/STT/TTS
/// categories exist here.
enum BenchmarkCategory {
  llm,
  stt,
  tts;

  String get displayName {
    switch (this) {
      case BenchmarkCategory.llm:
        return 'LLM';
      case BenchmarkCategory.stt:
        return 'STT';
      case BenchmarkCategory.tts:
        return 'TTS';
    }
  }

  sdk.ModelCategory get modelCategory {
    switch (this) {
      case BenchmarkCategory.llm:
        return sdk.ModelCategory.MODEL_CATEGORY_LANGUAGE;
      case BenchmarkCategory.stt:
        return sdk.ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION;
      case BenchmarkCategory.tts:
        return sdk.ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS;
    }
  }

  static BenchmarkCategory? fromName(String name) {
    for (final category in BenchmarkCategory.values) {
      if (category.name == name) return category;
    }
    return null;
  }
}

/// Status of one benchmark run (mirrors iOS `BenchmarkRunStatus`).
enum BenchmarkRunStatus {
  running,
  completed,
  failed,
  cancelled;

  static BenchmarkRunStatus fromName(String name) {
    for (final status in BenchmarkRunStatus.values) {
      if (status.name == name) return status;
    }
    return BenchmarkRunStatus.failed;
  }
}

/// One deterministic workload within a category (mirrors iOS
/// `BenchmarkScenario`).
class BenchmarkScenario {
  final String name;
  final BenchmarkCategory category;
  final Map<String, String>? parameters;

  const BenchmarkScenario({
    required this.name,
    required this.category,
    this.parameters,
  });

  String get id => '${category.name}_$name';

  Map<String, dynamic> toJson() => {
        'name': name,
        'category': category.name,
        if (parameters != null) 'parameters': parameters,
      };

  factory BenchmarkScenario.fromJson(Map<String, dynamic> json) {
    return BenchmarkScenario(
      name: json['name'] as String? ?? '',
      category: BenchmarkCategory.fromName(json['category'] as String? ?? '') ??
          BenchmarkCategory.llm,
      parameters: (json['parameters'] as Map<String, dynamic>?)?.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    );
  }
}

/// Snapshot of the benchmarked model for persistence (mirrors iOS
/// `ComponentModelInfo`).
class ComponentModelInfo {
  final String id;
  final String name;
  final String framework;
  final String category;

  const ComponentModelInfo({
    required this.id,
    required this.name,
    required this.framework,
    required this.category,
  });

  factory ComponentModelInfo.fromModel(sdk.ModelInfo model) {
    return ComponentModelInfo(
      id: model.id,
      name: model.name,
      framework: sdk.formatFramework(model.framework),
      category: model.category.name,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'framework': framework,
        'category': category,
      };

  factory ComponentModelInfo.fromJson(Map<String, dynamic> json) {
    return ComponentModelInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      framework: json['framework'] as String? ?? '',
      category: json['category'] as String? ?? '',
    );
  }
}

/// Device snapshot persisted with each run (mirrors iOS
/// `BenchmarkDeviceInfo`).
class BenchmarkDeviceInfo {
  final String modelName;
  final String chipName;
  final int totalMemoryBytes;
  final int availableMemoryBytes;
  final String osVersion;

  const BenchmarkDeviceInfo({
    required this.modelName,
    required this.chipName,
    required this.totalMemoryBytes,
    required this.availableMemoryBytes,
    required this.osVersion,
  });

  Map<String, dynamic> toJson() => {
        'modelName': modelName,
        'chipName': chipName,
        'totalMemoryBytes': totalMemoryBytes,
        'availableMemoryBytes': availableMemoryBytes,
        'osVersion': osVersion,
      };

  factory BenchmarkDeviceInfo.fromJson(Map<String, dynamic> json) {
    return BenchmarkDeviceInfo(
      modelName: json['modelName'] as String? ?? '',
      chipName: json['chipName'] as String? ?? '',
      totalMemoryBytes: (json['totalMemoryBytes'] as num?)?.toInt() ?? 0,
      availableMemoryBytes:
          (json['availableMemoryBytes'] as num?)?.toInt() ?? 0,
      osVersion: json['osVersion'] as String? ?? '',
    );
  }
}

/// Per-scenario metrics (mirrors iOS `BenchmarkMetrics`).
class BenchmarkMetrics {
  // Common
  double endToEndLatencyMs = 0;
  double loadTimeMs = 0;
  double warmupTimeMs = 0;
  int memoryDeltaBytes = 0;

  // LLM-specific
  double? ttftMs;
  double? tokensPerSecond;
  double? prefillTokensPerSecond;
  double? decodeTokensPerSecond;
  int? inputTokens;
  int? outputTokens;

  // STT-specific
  double? audioLengthSeconds;
  double? realTimeFactor;

  // TTS-specific
  double? audioDurationSeconds;
  int? charactersProcessed;

  // Error info
  String? errorMessage;

  BenchmarkMetrics();

  bool get didSucceed => errorMessage == null;

  Map<String, dynamic> toJson() => {
        'endToEndLatencyMs': endToEndLatencyMs,
        'loadTimeMs': loadTimeMs,
        'warmupTimeMs': warmupTimeMs,
        'memoryDeltaBytes': memoryDeltaBytes,
        if (ttftMs != null) 'ttftMs': ttftMs,
        if (tokensPerSecond != null) 'tokensPerSecond': tokensPerSecond,
        if (prefillTokensPerSecond != null)
          'prefillTokensPerSecond': prefillTokensPerSecond,
        if (decodeTokensPerSecond != null)
          'decodeTokensPerSecond': decodeTokensPerSecond,
        if (inputTokens != null) 'inputTokens': inputTokens,
        if (outputTokens != null) 'outputTokens': outputTokens,
        if (audioLengthSeconds != null)
          'audioLengthSeconds': audioLengthSeconds,
        if (realTimeFactor != null) 'realTimeFactor': realTimeFactor,
        if (audioDurationSeconds != null)
          'audioDurationSeconds': audioDurationSeconds,
        if (charactersProcessed != null)
          'charactersProcessed': charactersProcessed,
        if (errorMessage != null) 'errorMessage': errorMessage,
      };

  factory BenchmarkMetrics.fromJson(Map<String, dynamic> json) {
    final metrics = BenchmarkMetrics()
      ..endToEndLatencyMs =
          (json['endToEndLatencyMs'] as num?)?.toDouble() ?? 0
      ..loadTimeMs = (json['loadTimeMs'] as num?)?.toDouble() ?? 0
      ..warmupTimeMs = (json['warmupTimeMs'] as num?)?.toDouble() ?? 0
      ..memoryDeltaBytes = (json['memoryDeltaBytes'] as num?)?.toInt() ?? 0
      ..ttftMs = (json['ttftMs'] as num?)?.toDouble()
      ..tokensPerSecond = (json['tokensPerSecond'] as num?)?.toDouble()
      ..prefillTokensPerSecond =
          (json['prefillTokensPerSecond'] as num?)?.toDouble()
      ..decodeTokensPerSecond =
          (json['decodeTokensPerSecond'] as num?)?.toDouble()
      ..inputTokens = (json['inputTokens'] as num?)?.toInt()
      ..outputTokens = (json['outputTokens'] as num?)?.toInt()
      ..audioLengthSeconds = (json['audioLengthSeconds'] as num?)?.toDouble()
      ..realTimeFactor = (json['realTimeFactor'] as num?)?.toDouble()
      ..audioDurationSeconds =
          (json['audioDurationSeconds'] as num?)?.toDouble()
      ..charactersProcessed = (json['charactersProcessed'] as num?)?.toInt()
      ..errorMessage = json['errorMessage'] as String?;
    return metrics;
  }
}

int _benchmarkIdCounter = 0;

String _newBenchmarkId() =>
    '${DateTime.now().microsecondsSinceEpoch}_${_benchmarkIdCounter++}';

/// One scenario × model result (mirrors iOS `BenchmarkResult`).
class BenchmarkResult {
  final String id;
  final DateTime timestamp;
  final BenchmarkCategory category;
  final BenchmarkScenario scenario;
  final ComponentModelInfo modelInfo;
  final BenchmarkMetrics metrics;

  BenchmarkResult({
    required this.category,
    required this.scenario,
    required this.modelInfo,
    required this.metrics,
    String? id,
    DateTime? timestamp,
  })  : id = id ?? _newBenchmarkId(),
        timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'category': category.name,
        'scenario': scenario.toJson(),
        'modelInfo': modelInfo.toJson(),
        'metrics': metrics.toJson(),
      };

  factory BenchmarkResult.fromJson(Map<String, dynamic> json) {
    return BenchmarkResult(
      id: json['id'] as String?,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? ''),
      category: BenchmarkCategory.fromName(json['category'] as String? ?? '') ??
          BenchmarkCategory.llm,
      scenario: BenchmarkScenario.fromJson(
        (json['scenario'] as Map<String, dynamic>?) ?? const {},
      ),
      modelInfo: ComponentModelInfo.fromJson(
        (json['modelInfo'] as Map<String, dynamic>?) ?? const {},
      ),
      metrics: BenchmarkMetrics.fromJson(
        (json['metrics'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }
}

/// One full benchmark session (mirrors iOS `BenchmarkRun`).
class BenchmarkRun {
  final String id;
  final DateTime startedAt;
  DateTime? completedAt;
  List<BenchmarkResult> results;
  BenchmarkRunStatus status;
  final BenchmarkDeviceInfo deviceInfo;

  BenchmarkRun({
    required this.deviceInfo,
    String? id,
    DateTime? startedAt,
    List<BenchmarkResult>? results,
    this.completedAt,
    this.status = BenchmarkRunStatus.running,
  })  : id = id ?? _newBenchmarkId(),
        startedAt = startedAt ?? DateTime.now(),
        results = results ?? [];

  Duration? get duration => completedAt?.difference(startedAt);

  Map<String, dynamic> toJson() => {
        'id': id,
        'startedAt': startedAt.toIso8601String(),
        if (completedAt != null)
          'completedAt': completedAt!.toIso8601String(),
        'results': results.map((result) => result.toJson()).toList(),
        'status': status.name,
        'deviceInfo': deviceInfo.toJson(),
      };

  factory BenchmarkRun.fromJson(Map<String, dynamic> json) {
    return BenchmarkRun(
      id: json['id'] as String?,
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? ''),
      completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
      results: ((json['results'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(BenchmarkResult.fromJson)
          .toList(),
      status: BenchmarkRunStatus.fromName(json['status'] as String? ?? ''),
      deviceInfo: BenchmarkDeviceInfo.fromJson(
        (json['deviceInfo'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }
}

/// Output of one runner invocation: results plus categories skipped because
/// no downloaded models exist (mirrors iOS `BenchmarkRunOutput`).
class BenchmarkRunOutput {
  final List<BenchmarkResult> results;
  final List<BenchmarkCategory> skippedCategories;

  const BenchmarkRunOutput({
    required this.results,
    required this.skippedCategories,
  });
}

/// Live progress update emitted by the runner (mirrors iOS
/// `BenchmarkProgressUpdate`).
class BenchmarkProgressUpdate {
  final int completedCount;
  final int totalCount;
  final String currentScenario;
  final String currentModel;

  const BenchmarkProgressUpdate({
    required this.completedCount,
    required this.totalCount,
    required this.currentScenario,
    required this.currentModel,
  });

  double get progress => totalCount > 0 ? completedCount / totalCount : 0;
}
